# frozen_string_literal: true

RSpec.describe Internal::Companies::InvoicesController, type: :request do
  let(:company) { create(:company, equity_enabled: true) }
  let(:contractor) { create(:company_worker, company: company) }
  let(:user) { contractor.user }
  let(:admin) { create(:company_administrator, company: company).user }
  let(:expense_category) { create(:expense_category, company: company) }
  let(:invoice_params) do
    {
      invoice: {
        invoice_date: Date.current.to_s,
        invoice_number: "PDF-TEST-001",
        notes: "Invoice with PDF attachment"
      },
      invoice_line_items: [
        {
          description: "Development work",
          quantity: "10",
          hourly: "true",
          pay_rate_in_subunits: "6000"
        }
      ]
    }
  end
  let(:sample_pdf_path) { Rails.root.join("spec/fixtures/files/sample.pdf") }
  let(:pdf_file) { fixture_file_upload(sample_pdf_path, "application/pdf") }
  let(:non_pdf_file) { fixture_file_upload(sample_pdf_path, "image/jpeg") }
  let(:empty_pdf) { fixture_file_upload(Rails.root.join("spec/fixtures/files/empty.pdf"), "application/pdf") }

  before do
    sign_in(user)
    Current.user = user
    Current.company = company
    Current.company_worker = contractor
  end

  describe "POST /companies/:company_id/invoices" do
    context "with valid PDF attachment" do
      it "creates an invoice with a PDF attachment" do
        expect do
          post company_invoices_path(company), params: invoice_params.merge(invoice_pdf: pdf_file)
        end.to change(Invoice, :count).by(1)
          .and change(ActiveStorage::Attachment, :count).by(1)

        expect(response).to have_http_status(:created)
        
        # Verify the attachment was saved correctly
        invoice = Invoice.last
        expect(invoice.attachment).to be_present
        expect(invoice.attachment.filename.to_s).to eq("sample.pdf")
        expect(invoice.attachment.content_type).to eq("application/pdf")
      end

      it "creates an invoice without a PDF attachment when none is provided" do
        expect do
          post company_invoices_path(company), params: invoice_params
        end.to change(Invoice, :count).by(1)
          .and not_change(ActiveStorage::Attachment, :count)

        expect(response).to have_http_status(:created)
        
        invoice = Invoice.last
        expect(invoice.attachment).to be_nil
      end

      it "handles empty PDF files gracefully" do
        expect do
          post company_invoices_path(company), params: invoice_params.merge(invoice_pdf: empty_pdf)
        end.to change(Invoice, :count).by(1)
          .and change(ActiveStorage::Attachment, :count).by(1)

        expect(response).to have_http_status(:created)
        
        invoice = Invoice.last
        expect(invoice.attachment).to be_present
        expect(invoice.attachment.byte_size).to eq(0)
      end
    end

    context "with invalid PDF attachment" do
      it "rejects non-PDF files" do
        expect do
          post company_invoices_path(company), params: invoice_params.merge(invoice_pdf: non_pdf_file)
        end.not_to change(Invoice, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)).to include("error_message" => "Only PDF files are allowed for the invoice attachment")
      end

      it "handles nil file parameter gracefully" do
        expect do
          post company_invoices_path(company), params: invoice_params.merge(invoice_pdf: nil)
        end.to change(Invoice, :count).by(1)
          .and not_change(ActiveStorage::Attachment, :count)

        expect(response).to have_http_status(:created)
      end

      it "handles blank string file parameter gracefully" do
        expect do
          post company_invoices_path(company), params: invoice_params.merge(invoice_pdf: "")
        end.to change(Invoice, :count).by(1)
          .and not_change(ActiveStorage::Attachment, :count)

        expect(response).to have_http_status(:created)
      end
    end
  end

  describe "PATCH /companies/:company_id/invoices/:id" do
    let!(:invoice) { create(:invoice, company: company, user: user, company_worker: contractor) }

    context "with valid PDF attachment" do
      it "updates an invoice with a new PDF attachment" do
        expect do
          patch company_invoice_path(company, invoice.external_id), params: invoice_params.merge(invoice_pdf: pdf_file)
        end.to change { invoice.reload.attachment.present? }.from(false).to(true)
          .and change(ActiveStorage::Attachment, :count).by(1)

        expect(response).to have_http_status(:no_content)
        expect(invoice.reload.attachment.filename.to_s).to eq("sample.pdf")
      end

      it "replaces an existing PDF attachment" do
        # First attach an initial PDF
        invoice.attachments.attach(fixture_file_upload(sample_pdf_path, "application/pdf"))
        invoice.save!
        
        initial_attachment_id = invoice.attachment.id
        
        # Now update with a new PDF
        expect do
          patch company_invoice_path(company, invoice.external_id), params: invoice_params.merge(invoice_pdf: pdf_file)
        end.not_to change(ActiveStorage::Attachment, :count) # One is purged, one is added
        
        expect(response).to have_http_status(:no_content)
        invoice.reload
        expect(invoice.attachment).to be_present
        expect(invoice.attachment.id).not_to eq(initial_attachment_id)
      end

      it "keeps the existing attachment when no new PDF is provided" do
        # First attach an initial PDF
        invoice.attachments.attach(fixture_file_upload(sample_pdf_path, "application/pdf"))
        invoice.save!
        
        initial_attachment_id = invoice.attachment.id
        
        # Update without providing a new PDF
        expect do
          patch company_invoice_path(company, invoice.external_id), params: invoice_params
        end.not_to change(ActiveStorage::Attachment, :count)
        
        expect(response).to have_http_status(:no_content)
        invoice.reload
        expect(invoice.attachment).to be_present
        expect(invoice.attachment.id).to eq(initial_attachment_id)
      end
    end

    context "with invalid PDF attachment" do
      it "rejects non-PDF files" do
        expect do
          patch company_invoice_path(company, invoice.external_id), params: invoice_params.merge(invoice_pdf: non_pdf_file)
        end.not_to change { invoice.reload.attachment.present? }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)).to include("error_message" => "Only PDF files are allowed for the invoice attachment")
      end
    end
  end

  describe "GET /companies/:company_id/invoices/:id" do
    let!(:invoice) { create(:invoice, company: company, user: user, company_worker: contractor) }

    it "includes attachment information in the response" do
      # Attach a PDF to the invoice
      invoice.attachments.attach(fixture_file_upload(sample_pdf_path, "application/pdf"))
      invoice.save!

      get company_invoice_path(company, invoice.external_id)
      expect(response).to have_http_status(:ok)
      
      json_response = JSON.parse(response.body)
      expect(json_response["invoice"]).to include("attachment")
      expect(json_response["invoice"]["attachment"]).to include("name", "url")
      expect(json_response["invoice"]["attachment"]["name"]).to eq("invoice.pdf")
    end

    it "returns null attachment when no PDF is attached" do
      get company_invoice_path(company, invoice.external_id)
      expect(response).to have_http_status(:ok)
      
      json_response = JSON.parse(response.body)
      expect(json_response["invoice"]["attachment"]).to be_nil
    end
  end

  describe "authorization" do
    it "prevents unauthorized users from accessing invoices with PDFs" do
      other_user = create(:user)
      sign_in(other_user)
      Current.user = other_user

      invoice = create(:invoice, company: company, user: user, company_worker: contractor)
      invoice.attachments.attach(fixture_file_upload(sample_pdf_path, "application/pdf"))
      invoice.save!

      get company_invoice_path(company, invoice.external_id)
      expect(response).to have_http_status(:not_found)
    end
  end

  # Helper to test if something changes
  def not_change(receiver = nil, &block)
    if receiver
      expect { yield }.not_to change { receiver }
    else
      expect { yield }.not_to change(&block)
    end
  end
end
