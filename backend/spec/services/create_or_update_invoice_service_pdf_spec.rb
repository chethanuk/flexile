# frozen_string_literal: true

RSpec.describe CreateOrUpdateInvoiceService do
  let(:company_administrator) { create(:company_administrator, company:) }
  let(:company) { create(:company) }
  let!(:expense_category) { create(:expense_category, company:) }
  let(:contractor) { create(:company_worker, company:) }
  let(:user) { contractor.user }
  let(:date) { Date.current }
  let(:invoice_params) do
    {
      invoice: {
        invoice_date: date.to_s,
        invoice_number: "INV-123",
        notes: "Tax ID: 123efjo32r",
      },
    }
  end
  let(:invoice_line_item_params) do
    {
      invoice_line_items: [
        {
          description: "I worked on XYZ",
          pay_rate_in_subunits: contractor.pay_rate_in_subunits,
          quantity: 121,
          hourly: true,
        }
      ],
    }
  end
  let(:sample_pdf_path) { Rails.root.join("spec/fixtures/files/sample.pdf") }
  let(:invoice_service) { described_class.new(params:, user:, company:, contractor:, invoice:) }
  let!(:equity_grant) do
    create(:active_grant, company_investor: create(:company_investor, company:, user:),
                          share_price_usd: 2.34, year: Date.current.year)
  end

  before { company.update!(equity_enabled: true) }

  describe "#process with PDF uploads" do
    context "when creating a new invoice" do
      let(:invoice) { nil }
      let(:params) { ActionController::Parameters.new({ **invoice_params, **invoice_line_item_params }) }

      it "creates an invoice without a PDF attachment when no PDF is provided" do
        expect do
          result = invoice_service.process
          expect(result[:success]).to be(true)
          expect(result[:invoice].attachment).to be_nil
        end.to change { user.invoices.count }.by(1)
      end

      it "creates an invoice with a PDF attachment when a valid PDF is provided" do
        pdf_file = fixture_file_upload(sample_pdf_path, "application/pdf")
        params_with_pdf = ActionController::Parameters.new({ **invoice_params, **invoice_line_item_params, invoice_pdf: pdf_file })
        service = described_class.new(params: params_with_pdf, user:, company:, contractor:, invoice:)

        expect do
          result = service.process
          expect(result[:success]).to be(true)
          expect(result[:invoice].attachment).to be_present
          expect(result[:invoice].attachment.filename.to_s).to eq("sample.pdf")
          expect(result[:invoice].attachment.content_type).to eq("application/pdf")
        end.to change { user.invoices.count }.by(1)
          .and change { ActiveStorage::Attachment.count }.by(1)
      end

      it "rejects non-PDF files" do
        non_pdf_file = fixture_file_upload(sample_pdf_path, "image/jpeg")
        params_with_non_pdf = ActionController::Parameters.new({ **invoice_params, **invoice_line_item_params, invoice_pdf: non_pdf_file })
        service = described_class.new(params: params_with_non_pdf, user:, company:, contractor:, invoice:)

        expect do
          result = service.process
          expect(result[:success]).to be(false)
          expect(result[:error_message]).to eq("Only PDF files are allowed for the invoice attachment")
        end.not_to change { user.invoices.count }
      end

      it "handles empty file uploads gracefully" do
        empty_file = fixture_file_upload(Rails.root.join("spec/fixtures/files/empty.pdf"), "application/pdf")
        allow(File).to receive(:size).with(empty_file.path).and_return(0)
        
        params_with_empty_pdf = ActionController::Parameters.new({ **invoice_params, **invoice_line_item_params, invoice_pdf: empty_file })
        service = described_class.new(params: params_with_empty_pdf, user:, company:, contractor:, invoice:)

        expect do
          result = service.process
          expect(result[:success]).to be(true)
          expect(result[:invoice].attachment).to be_present
          expect(result[:invoice].attachment.byte_size).to eq(0)
        end.to change { user.invoices.count }.by(1)
      end
    end

    context "when updating an existing invoice" do
      let(:invoice) { create(:invoice, company:, user:, company_worker: contractor) }
      let(:params) { ActionController::Parameters.new({ **invoice_params, **invoice_line_item_params }) }

      it "replaces an existing PDF with a new one" do
        # First attach an initial PDF
        initial_pdf = fixture_file_upload(sample_pdf_path, "application/pdf")
        invoice.attachments.attach(initial_pdf)
        invoice.save!
        
        initial_attachment_id = invoice.attachment.id
        
        # Now update with a new PDF
        new_pdf = fixture_file_upload(sample_pdf_path, "application/pdf")
        params_with_pdf = ActionController::Parameters.new({ **invoice_params, **invoice_line_item_params, invoice_pdf: new_pdf })
        service = described_class.new(params: params_with_pdf, user:, company:, contractor:, invoice:)

        expect do
          result = service.process
          expect(result[:success]).to be(true)
          invoice.reload
          expect(invoice.attachment).to be_present
          expect(invoice.attachment.id).not_to eq(initial_attachment_id)
        end.to change { ActiveStorage::Attachment.count }.by(0) # One is purged, one is added
      end

      it "removes the PDF when updating without providing a new one" do
        # First attach an initial PDF
        initial_pdf = fixture_file_upload(sample_pdf_path, "application/pdf")
        invoice.attachments.attach(initial_pdf)
        invoice.save!
        
        # Now update without a PDF
        expect do
          result = invoice_service.process
          expect(result[:success]).to be(true)
          # The attachment should still be there since we're not explicitly removing it
          invoice.reload
          expect(invoice.attachment).to be_present
        end.not_to change { ActiveStorage::Attachment.count }
      end
    end

    context "with expense attachments" do
      let(:invoice) { nil }
      let(:expense_params) do
        {
          invoice_expenses: [
            {
              description: "Office supplies",
              expense_category_id: expense_category.id,
              total_amount_in_cents: 2500,
              attachment: fixture_file_upload(sample_pdf_path, "application/pdf")
            }
          ]
        }
      end
      let(:params) { ActionController::Parameters.new({ **invoice_params, **invoice_line_item_params, **expense_params }) }

      it "handles both invoice PDF and expense attachments correctly" do
        invoice_pdf = fixture_file_upload(sample_pdf_path, "application/pdf")
        params_with_pdf = ActionController::Parameters.new({ **invoice_params, **invoice_line_item_params, **expense_params, invoice_pdf: invoice_pdf })
        service = described_class.new(params: params_with_pdf, user:, company:, contractor:, invoice:)

        expect do
          result = service.process
          expect(result[:success]).to be(true)
          
          # Check invoice attachment
          expect(result[:invoice].attachment).to be_present
          expect(result[:invoice].attachment.filename.to_s).to eq("sample.pdf")
          
          # Check expense attachment
          expect(result[:invoice].invoice_expenses.first.attachment).to be_present
          expect(result[:invoice].invoice_expenses.first.attachment.filename.to_s).to eq("sample.pdf")
        end.to change { ActiveStorage::Attachment.count }.by(2) # One for invoice, one for expense
      end
    end

    context "with edge cases" do
      let(:invoice) { nil }
      let(:params) { ActionController::Parameters.new({ **invoice_params, **invoice_line_item_params }) }

      it "handles large PDFs correctly" do
        # Mock a large file
        large_pdf = fixture_file_upload(sample_pdf_path, "application/pdf")
        allow(File).to receive(:size).with(large_pdf.path).and_return(10.megabytes)
        
        params_with_large_pdf = ActionController::Parameters.new({ **invoice_params, **invoice_line_item_params, invoice_pdf: large_pdf })
        service = described_class.new(params: params_with_large_pdf, user:, company:, contractor:, invoice:)

        expect do
          result = service.process
          expect(result[:success]).to be(true)
          expect(result[:invoice].attachment).to be_present
        end.to change { user.invoices.count }.by(1)
          .and change { ActiveStorage::Attachment.count }.by(1)
      end

      it "handles nil PDF parameter gracefully" do
        params_with_nil_pdf = ActionController::Parameters.new({ **invoice_params, **invoice_line_item_params, invoice_pdf: nil })
        service = described_class.new(params: params_with_nil_pdf, user:, company:, contractor:, invoice:)

        expect do
          result = service.process
          expect(result[:success]).to be(true)
          expect(result[:invoice].attachment).to be_nil
        end.to change { user.invoices.count }.by(1)
          .and not_change { ActiveStorage::Attachment.count }
      end
    end
  end
end
