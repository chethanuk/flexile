# frozen_string_literal: true

require "spec_helper"
require_relative "../support/pdf_test_helpers"

RSpec.describe CreateOrUpdateInvoiceService do
  include PDFTestHelpers

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
  let!(:equity_grant) do
    create(:active_grant, company_investor: create(:company_investor, company:, user:),
                          share_price_usd: 2.34, year: Date.current.year)
  end

  # Temporary files for cleanup
  let(:temp_files) { [] }

  before do
    company.update!(equity_enabled: true)
  end

  after do
    # Clean up any temporary files created during tests
    temp_files.each do |file|
      file.close
      file.unlink
    end
  end

  # Helper to create a PDF fixture and track for cleanup
  def create_pdf_fixture(pdf_method, *args)
    file = send(pdf_method, *args)
    temp_files << file
    pdf_fixture_upload(file)
  end

  # Shared examples for testing PDF upload scenarios
  shared_examples "handles PDF upload correctly" do |scenario|
    let(:invoice) { scenario[:existing_invoice] }
    let(:base_params) { ActionController::Parameters.new({ **invoice_params, **invoice_line_item_params }) }
    
    it "#{scenario[:description]}" do
      # Setup PDF file based on scenario
      pdf_file = if scenario[:pdf_file].is_a?(Symbol)
                   create_pdf_fixture(scenario[:pdf_file], *scenario[:pdf_args])
                 else
                   scenario[:pdf_file]
                 end
      
      # Setup params with PDF if provided
      params_with_pdf = if pdf_file
                          base_params.merge(invoice_pdf: pdf_file)
                        else
                          base_params
                        end
      
      service = described_class.new(
        params: params_with_pdf,
        user: user,
        company: company,
        contractor: contractor,
        invoice: invoice
      )
      
      # Execute with expectations
      expect do
        result = service.process
        
        if scenario[:expected_success]
          expect(result[:success]).to be(true), "Expected success but got error: #{result[:error_message]}"
          
          if scenario[:verify_attachment]
            if scenario[:should_have_attachment]
              expect(result[:invoice].attachment).to be_present, "Expected attachment to be present"
              scenario[:attachment_expectations]&.each do |expectation|
                instance_exec(result[:invoice].attachment, &expectation)
              end
            else
              expect(result[:invoice].attachment).to be_nil, "Expected no attachment"
            end
          end
        else
          expect(result[:success]).to be(false), "Expected failure but got success"
          expect(result[:error_message]).to eq(scenario[:expected_error])
        end
      end.to change { scenario[:change_expectation].call }
    end
  end

  describe "#process with PDF uploads" do
    context "when creating a new invoice" do
      # Define test scenarios for parametrized tests
      invoice_creation_scenarios = [
        {
          description: "creates an invoice without a PDF attachment when no PDF is provided",
          existing_invoice: nil,
          pdf_file: nil,
          expected_success: true,
          should_have_attachment: false,
          verify_attachment: true,
          change_expectation: -> { expect(user.invoices).to change { user.invoices.count }.by(1) }
        },
        {
          description: "creates an invoice with a standard invoice PDF",
          existing_invoice: nil,
          pdf_file: :create_invoice_pdf,
          pdf_args: [],
          expected_success: true,
          should_have_attachment: true,
          verify_attachment: true,
          attachment_expectations: [
            ->(attachment) { expect(attachment.content_type).to eq("application/pdf") },
            ->(attachment) { expect(valid_pdf?(attachment.blob)).to be true }
          ],
          change_expectation: -> { 
            expect(user.invoices).to change { user.invoices.count }.by(1)
            .and change { ActiveStorage::Attachment.count }.by(1) 
          }
        },
        {
          description: "creates an invoice with a minimal empty PDF",
          existing_invoice: nil,
          pdf_file: :create_empty_pdf,
          pdf_args: [],
          expected_success: true,
          should_have_attachment: true,
          verify_attachment: true,
          attachment_expectations: [
            ->(attachment) { expect(attachment.content_type).to eq("application/pdf") }
          ],
          change_expectation: -> { 
            expect(user.invoices).to change { user.invoices.count }.by(1)
            .and change { ActiveStorage::Attachment.count }.by(1) 
          }
        },
        {
          description: "rejects non-PDF files with PDF extension",
          existing_invoice: nil,
          pdf_file: :create_fake_pdf,
          pdf_args: [],
          expected_success: false,
          expected_error: "Only PDF files are allowed for the invoice attachment",
          change_expectation: -> { expect(user.invoices).not_to change { user.invoices.count } }
        },
        {
          description: "handles zero-byte PDF files gracefully",
          existing_invoice: nil,
          pdf_file: :create_zero_byte_pdf,
          pdf_args: [],
          expected_success: true,
          should_have_attachment: false, # Zero-byte files are ignored
          verify_attachment: true,
          change_expectation: -> { 
            expect(user.invoices).to change { user.invoices.count }.by(1)
            .and not_change { ActiveStorage::Attachment.count } 
          }
        },
        {
          description: "handles large PDF files correctly (under 2MB limit)",
          existing_invoice: nil,
          pdf_file: :create_large_pdf,
          pdf_args: [1.5], # 1.5MB PDF
          expected_success: true,
          should_have_attachment: true,
          verify_attachment: true,
          attachment_expectations: [
            ->(attachment) { expect(attachment.content_type).to eq("application/pdf") },
            ->(attachment) { expect(attachment.byte_size).to be > 500_000 } # Should be significantly large
          ],
          change_expectation: -> { 
            expect(user.invoices).to change { user.invoices.count }.by(1)
            .and change { ActiveStorage::Attachment.count }.by(1) 
          }
        },
        {
          description: "rejects PDF files exceeding the 2MB limit",
          existing_invoice: nil,
          pdf_file: :create_large_pdf,
          pdf_args: [2.5], # 2.5MB PDF (exceeds 2MB limit)
          expected_success: false,
          expected_error: "PDF file size exceeds the 2MB limit",
          change_expectation: -> { expect(user.invoices).not_to change { user.invoices.count } }
        },
        {
          description: "rejects corrupted PDF files",
          existing_invoice: nil,
          pdf_file: :create_corrupted_pdf,
          pdf_args: [],
          expected_success: false,
          expected_error: "Only PDF files are allowed for the invoice attachment",
          change_expectation: -> { expect(user.invoices).not_to change { user.invoices.count } }
        }
      ]

      # Run all scenarios
      invoice_creation_scenarios.each do |scenario|
        include_examples "handles PDF upload correctly", scenario
      end
    end

    context "when updating an existing invoice" do
      let(:existing_invoice) { create(:invoice, company:, user:, company_worker: contractor) }
      let(:with_initial_pdf) do
        pdf = create_invoice_pdf
        temp_files << pdf
        existing_invoice.attachments.attach(pdf_fixture_upload(pdf))
        existing_invoice.save!
        existing_invoice
      end

      # Define test scenarios for parametrized tests
      invoice_update_scenarios = [
        {
          description: "replaces an existing PDF with a new one",
          existing_invoice: -> { with_initial_pdf },
          pdf_file: :create_invoice_pdf,
          pdf_args: [{ title: "REPLACEMENT INVOICE" }],
          expected_success: true,
          should_have_attachment: true,
          verify_attachment: true,
          attachment_expectations: [
            ->(attachment) { 
              expect(attachment.content_type).to eq("application/pdf")
              expect(pdf_contains_text?(attachment.blob, "REPLACEMENT INVOICE")).to be true
            }
          ],
          change_expectation: -> { 
            initial_id = with_initial_pdf.attachment.id
            expect { with_initial_pdf.reload }.to change { with_initial_pdf.attachment.id }.from(initial_id)
          }
        },
        {
          description: "keeps existing PDF when updating without providing a new one",
          existing_invoice: -> { with_initial_pdf },
          pdf_file: nil,
          expected_success: true,
          should_have_attachment: true,
          verify_attachment: true,
          attachment_expectations: [
            ->(attachment) { expect(attachment.id).to eq(with_initial_pdf.attachment.id) }
          ],
          change_expectation: -> { expect(ActiveStorage::Attachment.count).not_to change }
        },
        {
          description: "rejects non-PDF files when updating",
          existing_invoice: -> { existing_invoice },
          pdf_file: :create_fake_pdf,
          pdf_args: [],
          expected_success: false,
          expected_error: "Only PDF files are allowed for the invoice attachment",
          change_expectation: -> { expect(ActiveStorage::Attachment.count).not_to change }
        },
        {
          description: "rejects oversized PDF files when updating",
          existing_invoice: -> { existing_invoice },
          pdf_file: :create_large_pdf,
          pdf_args: [2.5], # 2.5MB PDF (exceeds 2MB limit)
          expected_success: false,
          expected_error: "PDF file size exceeds the 2MB limit",
          change_expectation: -> { expect(ActiveStorage::Attachment.count).not_to change }
        }
      ]

      # Run all scenarios
      invoice_update_scenarios.each do |scenario|
        # Handle dynamic invoice setup
        if scenario[:existing_invoice].respond_to?(:call)
          let(:invoice) { instance_eval(&scenario[:existing_invoice]) }
        else
          let(:invoice) { scenario[:existing_invoice] }
        end
        
        include_examples "handles PDF upload correctly", scenario
      end
    end

    context "with expense attachments" do
      let(:invoice) { nil }
      
      it "handles both invoice PDF and expense attachments correctly" do
        # Create PDFs for invoice and expense
        invoice_pdf = create_invoice_pdf
        expense_pdf = create_invoice_pdf(title: "EXPENSE")
        temp_files.concat([invoice_pdf, expense_pdf])
        
        expense_params = {
          invoice_expenses: [
            {
              description: "Office supplies",
              expense_category_id: expense_category.id,
              total_amount_in_cents: 2500,
              attachment: pdf_fixture_upload(expense_pdf)
            }
          ]
        }
        
        params = ActionController::Parameters.new({
          **invoice_params,
          **invoice_line_item_params,
          **expense_params,
          invoice_pdf: pdf_fixture_upload(invoice_pdf)
        })
        
        service = described_class.new(
          params: params,
          user: user,
          company: company,
          contractor: contractor,
          invoice: invoice
        )
        
        expect do
          result = service.process
          expect(result[:success]).to be(true)
          
          # Check invoice attachment
          expect(result[:invoice].attachment).to be_present
          expect(result[:invoice].attachment.content_type).to eq("application/pdf")
          
          # Check expense attachment
          expect(result[:invoice].invoice_expenses.first.attachment).to be_present
          expect(result[:invoice].invoice_expenses.first.attachment.content_type).to eq("application/pdf")
        end.to change { ActiveStorage::Attachment.count }.by(2) # One for invoice, one for expense
      end
    end

    context "with edge cases" do
      # Define edge case scenarios
      edge_case_scenarios = [
        {
          description: "handles nil PDF parameter gracefully",
          existing_invoice: nil,
          pdf_file: nil,
          expected_success: true,
          should_have_attachment: false,
          verify_attachment: true,
          change_expectation: -> { 
            expect(user.invoices).to change { user.invoices.count }.by(1)
            .and not_change { ActiveStorage::Attachment.count } 
          }
        },
        {
          description: "handles empty string as PDF parameter gracefully",
          existing_invoice: nil,
          pdf_file: "",
          expected_success: true,
          should_have_attachment: false,
          verify_attachment: true,
          change_expectation: -> { 
            expect(user.invoices).to change { user.invoices.count }.by(1)
            .and not_change { ActiveStorage::Attachment.count } 
          }
        }
      ]

      # Run all edge case scenarios
      edge_case_scenarios.each do |scenario|
        include_examples "handles PDF upload correctly", scenario
      end
    end
  end

  # Helper to test if something doesn't change
  def not_change(&block)
    expect { yield }.not_to change(&block)
  end
end
