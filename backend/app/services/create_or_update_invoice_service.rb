# frozen_string_literal: true

class CreateOrUpdateInvoiceService
  delegate :street_address, :city, :state, :zip_code, :country_code, to: :user, private: true

  def initialize(params:, user:, company:, contractor:, invoice: nil)
    @params = params
    @contractor = contractor
    @user = user
    @invoice = invoice || Invoice.new(user:, company:, company_worker: contractor)
  end

  def process
    error = nil
    ApplicationRecord.transaction do
      existing_line_items = invoice.invoice_line_items.to_a
      line_items_to_keep = []
      invoice.assign_attributes(status: Invoice::RECEIVED, invoice_date: Date.current,
                                street_address:, city:, state:, zip_code:, country_code:,
                                invoice_number: invoice.recommended_invoice_number, created_by: user,
                                **invoice_params)
      invoice.total_amount_in_usd_cents = 0
      if invoice_line_items_params.present?
        invoice_line_items_params.each do |line_item|
          invoice_line_item = invoice.invoice_line_items.find_by(id: line_item[:id]) ||
                              invoice.invoice_line_items.build(line_item)
          if invoice_line_item.persisted?
            # TODO (raul): remove once https://github.com/rails/rails/issues/17466 is fixed
            #   Ensures changed association is saved when calling @invoice.save.
            invoice.association(:invoice_line_items).add_to_target(invoice_line_item)
            invoice_line_item.assign_attributes(**line_item.except(:id))
          end

          line_items_to_keep << invoice_line_item
          invoice.total_amount_in_usd_cents += invoice_line_item.total_amount_cents
        end
      end
      line_items_to_remove = existing_line_items - line_items_to_keep
      line_items_to_remove.each(&:mark_for_destruction)

      existing_expenses = invoice.invoice_expenses.to_a
      keep_expenses = []
      expenses_in_cents = 0
      invoice_expenses_params.each do |expense|
        invoice_expense = invoice.invoice_expenses.find_by(id: expense[:id]) || invoice.invoice_expenses.build(expense)
        if invoice_expense.persisted?
          # TODO (raul): remove once https://github.com/rails/rails/issues/17466 is fixed
          #   Ensures changed association is saved when calling @invoice.save.
          invoice.association(:invoice_expenses).add_to_target(invoice_expense, replace: true)
          invoice_expense.assign_attributes(**expense.except(:id, :attachment))
        end
        keep_expenses << invoice_expense
        invoice.total_amount_in_usd_cents += expense[:total_amount_in_cents].to_i
        expenses_in_cents += expense[:total_amount_in_cents].to_i
      end
      expenses_to_remove = existing_expenses - keep_expenses
      expenses_to_remove.each(&:mark_for_destruction)

      services_in_cents = invoice.total_amount_in_usd_cents - expenses_in_cents
      invoice_year = invoice.invoice_date.year
      equity_calculation_result = InvoiceEquityCalculator.new(
        company_worker: contractor,
        company: invoice.company,
        service_amount_cents: services_in_cents,
        invoice_year:,
      ).calculate
      if equity_calculation_result.nil?
        error = "Something went wrong. Please contact the company administrator."
        raise ActiveRecord::Rollback
      end

      equity_calculation_result => { equity_cents:, equity_options:, equity_percentage: }
      invoice.equity_percentage = equity_percentage
      invoice.cash_amount_in_cents = invoice.total_amount_in_usd_cents - equity_cents
      invoice.equity_amount_in_cents = equity_cents
      invoice.equity_amount_in_options = equity_options
      invoice.flexile_fee_cents = invoice.calculate_flexile_fee_cents

      # Handle PDF upload after equity calculations but before saving
      pdf_error = handle_pdf_upload
      if pdf_error.present?
        error = pdf_error
        raise ActiveRecord::Rollback
      end

      unless invoice.save
        error = invoice.errors.full_messages.to_sentence
        raise ActiveRecord::Rollback
      end
    end
    if error.present?
      {
        success: false,
        error_message: error,
      }
    else
      {
        success: true,
        invoice: invoice,
      }
    end
  end

  private
    attr_reader :params, :invoice, :contractor, :user

    def invoice_params
      params.permit(invoice: [:invoice_date, :invoice_number, :notes, :equity_percentage])[:invoice]
    end

    def invoice_line_items_params
      permitted_params = [:id, :description, :quantity, :pay_rate_in_subunits, :hourly]

      params.permit(invoice_line_items: permitted_params).fetch(:invoice_line_items, [])
    end

    def invoice_expenses_params
      return [] unless params[:invoice_expenses].present?

      params.permit(invoice_expenses: [:id, :description, :expense_category_id, :total_amount_in_cents, :attachment])
            .fetch(:invoice_expenses)
    end

    # Handle PDF upload for the invoice
    # @return [String, nil] Error message if validation fails, nil if successful
    def handle_pdf_upload
      uploaded_pdf = invoice_pdf_param
      return nil unless uploaded_pdf # Skip if no PDF provided

      # Validate content type
      unless uploaded_pdf.respond_to?(:content_type) && uploaded_pdf.content_type == "application/pdf"
        return "Only PDF files are allowed for the invoice attachment"
      end

      # Validate file size (2MB limit)
      if uploaded_pdf.respond_to?(:size) && uploaded_pdf.size > 2.megabytes
        return "PDF file size exceeds the 2MB limit"
      end

      # Replace any existing attachment
      invoice.attachments.each(&:purge_later) if invoice.attachments.attached?
      invoice.attachments.attach(uploaded_pdf)
      
      nil # No errors
    end

    # Single PDF uploaded for the entire invoice (not for individual expenses)
    def invoice_pdf_param
      file = params.permit(:invoice_pdf)[:invoice_pdf]

      # 1. Explicit nil check (fast-path)
      return nil if file.nil?

      # 2. Respect Rails' `blank?` when available
      return nil if file.respond_to?(:blank?) && file.blank?

      # 3. Fallback for plain strings when `blank?` is unavailable
      return nil if file.is_a?(String) && file.strip.empty?

      # 4. Ignore zero-byte uploads
      return nil if file.respond_to?(:size) && file.size.to_i.zero?

      file
    end
end
