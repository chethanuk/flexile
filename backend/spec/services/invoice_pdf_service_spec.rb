# frozen_string_literal: true

RSpec.describe CreateOrUpdateInvoiceService, "#invoice_pdf_handling" do
  let(:user) { instance_double("User") }
  let(:company) { instance_double("Company") }
  let(:contractor) { instance_double("CompanyWorker", company: company) }
  let(:invoice) { instance_double("Invoice", attachments: attachments) }
  let(:attachments) { instance_double("ActiveStorage::Attached::Many") }
  let(:pdf_file) { instance_double("ActionDispatch::Http::UploadedFile", content_type: "application/pdf") }
  let(:non_pdf_file) { instance_double("ActionDispatch::Http::UploadedFile", content_type: "image/jpeg") }
  
  subject(:service) { described_class.new(params: params, user: user, company: company, contractor: contractor, invoice: invoice) }

  describe "PDF upload handling" do
    before do
      # Setup minimal stubs to isolate PDF handling logic
      allow(service).to receive(:invoice_params).and_return({})
      allow(service).to receive(:invoice_line_items_params).and_return([])
      allow(service).to receive(:invoice_expenses_params).and_return([])
      allow(invoice).to receive(:invoice_line_items).and_return([])
      allow(invoice).to receive(:invoice_expenses).and_return([])
      allow(invoice).to receive(:assign_attributes)
      allow(invoice).to receive(:total_amount_in_usd_cents=)
      allow(invoice).to receive(:equity_percentage=)
      allow(invoice).to receive(:cash_amount_in_cents=)
      allow(invoice).to receive(:equity_amount_in_cents=)
      allow(invoice).to receive(:equity_amount_in_options=)
      allow(invoice).to receive(:flexile_fee_cents=)
      allow(invoice).to receive(:save).and_return(true)
      
      # Allow transaction to execute normally
      allow(ApplicationRecord).to receive(:transaction).and_yield
    end

    context "when a valid PDF file is uploaded" do
      let(:params) { ActionController::Parameters.new({ invoice_pdf: pdf_file }) }
      
      it "attaches the PDF to the invoice" do
        expect(attachments).to receive(:each).and_yield(double.as_null_object) # For purge_later
        expect(attachments).to receive(:attach).with(pdf_file)
        
        result = service.process
        expect(result[:success]).to be(true)
      end
      
      it "purges existing attachments" do
        existing_attachment = double("Attachment")
        expect(attachments).to receive(:each).and_yield(existing_attachment)
        expect(existing_attachment).to receive(:purge_later)
        expect(attachments).to receive(:attach).with(pdf_file)
        
        service.process
      end
    end
    
    context "when a non-PDF file is uploaded" do
      let(:params) { ActionController::Parameters.new({ invoice_pdf: non_pdf_file }) }
      
      it "raises an error and does not attach the file" do
        expect(attachments).not_to receive(:attach)
        expect(ApplicationRecord).to receive(:transaction).and_raise(ActiveRecord::Rollback)
        
        result = service.process
        expect(result[:success]).to be(false)
        expect(result[:error_message]).to eq("Only PDF files are allowed for the invoice attachment")
      end
    end
    
    context "when no file is uploaded" do
      let(:params) { ActionController::Parameters.new({}) }
      
      it "does not attempt to attach or purge any files" do
        expect(attachments).not_to receive(:each)
        expect(attachments).not_to receive(:attach)
        
        result = service.process
        expect(result[:success]).to be(true)
      end
    end
    
    context "when handling edge cases" do
      context "with nil params" do
        let(:params) { ActionController::Parameters.new({ invoice_pdf: nil }) }
        
        it "handles nil file gracefully" do
          expect(attachments).not_to receive(:attach)
          
          result = service.process
          expect(result[:success]).to be(true)
        end
      end
      
      context "with empty params" do
        let(:params) { ActionController::Parameters.new({ invoice_pdf: "" }) }
        
        it "handles empty string gracefully" do
          expect(attachments).not_to receive(:attach)
          
          result = service.process
          expect(result[:success]).to be(true)
        end
      end
    end
  end
end
