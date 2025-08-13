# frozen_string_literal: true

require "prawn"
require "tempfile"

# Module for PDF testing helpers
# Provides methods to generate test PDFs and validate PDF content
module PDFTestHelpers
  # Creates a valid invoice PDF with customizable content
  # @param options [Hash] Options for PDF generation
  # @option options [String] :title Invoice title
  # @option options [String] :invoice_number Invoice number
  # @option options [Date] :date Invoice date
  # @option options [String] :company_name Company name
  # @option options [String] :contractor_name Contractor name
  # @option options [Array<Hash>] :line_items Line items with :description, :quantity, :rate
  # @option options [Integer] :total_amount Total amount in cents
  # @return [Tempfile] Temporary file containing the PDF
  def create_invoice_pdf(options = {})
    options = default_invoice_options.merge(options)
    
    pdf_file = Tempfile.new(["invoice", ".pdf"])
    
    Prawn::Document.generate(pdf_file.path) do |pdf|
      # Header
      pdf.font_size(20) { pdf.text options[:title], align: :center }
      pdf.move_down 20
      
      # Invoice details
      pdf.text "Invoice #: #{options[:invoice_number]}"
      pdf.text "Date: #{options[:date]}"
      pdf.move_down 10
      
      # Company and contractor info
      pdf.text "From: #{options[:contractor_name]}"
      pdf.text "To: #{options[:company_name]}"
      pdf.move_down 20
      
      # Line items
      if options[:line_items].any?
        pdf.table(line_items_data(options[:line_items]), header: true, width: pdf.bounds.width) do
          row(0).font_style = :bold
        end
      end
      
      # Total
      pdf.move_down 10
      pdf.text "Total: $#{format("%.2f", options[:total_amount] / 100.0)}", align: :right
      
      # Footer
      pdf.move_down 30
      pdf.text "Thank you for your business!", align: :center, size: 14
    end
    
    pdf_file.rewind
    pdf_file
  end
  
  # Creates an empty but valid PDF file
  # @return [Tempfile] Empty PDF file
  def create_empty_pdf
    pdf_file = Tempfile.new(["empty", ".pdf"])
    
    Prawn::Document.generate(pdf_file.path) do |pdf|
      # Create an empty PDF with just the required PDF structure
    end
    
    pdf_file.rewind
    pdf_file
  end
  
  # Creates a very large PDF file for testing size limits
  # @param size_in_mb [Integer] Approximate size of the PDF in MB
  # @return [Tempfile] Large PDF file
  def create_large_pdf(size_in_mb = 5)
    pdf_file = Tempfile.new(["large", ".pdf"])
    
    Prawn::Document.generate(pdf_file.path) do |pdf|
      pdf.font_size(12) { pdf.text "Large PDF Test File", align: :center }
      
      # Generate content to reach approximate size
      # Each iteration adds roughly 100KB
      iterations = (size_in_mb * 10)
      iterations.times do |i|
        pdf.start_new_page if (i % 5).zero?
        pdf.text "Page content #{i} " * 100
        pdf.image dummy_image_path, width: 300 if File.exist?(dummy_image_path) && (i % 3).zero?
      end
    end
    
    pdf_file.rewind
    pdf_file
  end
  
  # Creates a non-PDF file (actually just text with PDF extension)
  # @return [Tempfile] Non-PDF file with PDF extension
  def create_fake_pdf
    file = Tempfile.new(["fake", ".pdf"])
    file.write("This is not a real PDF file but has a .pdf extension")
    file.rewind
    file
  end
  
  # Creates a corrupted PDF file
  # @return [Tempfile] Corrupted PDF file
  def create_corrupted_pdf
    file = Tempfile.new(["corrupted", ".pdf"])
    file.write("%PDF-1.4\nThis is a corrupted PDF file with invalid structure")
    file.rewind
    file
  end
  
  # Creates a zero-byte PDF file
  # @return [Tempfile] Zero-byte file with PDF extension
  def create_zero_byte_pdf
    file = Tempfile.new(["zero", ".pdf"])
    file.close
    file
  end
  
  # Verifies if a file is a valid PDF
  # @param file [File, Tempfile, String] File object or path to check
  # @return [Boolean] True if valid PDF, false otherwise
  def valid_pdf?(file)
    path = file.respond_to?(:path) ? file.path : file
    
    begin
      header = File.open(path, "rb") { |f| f.read(5) }
      return header == "%PDF-"
    rescue StandardError
      return false
    end
  end
  
  # Checks if a PDF contains specific text
  # @param file [File, Tempfile, String] PDF file or path
  # @param text [String] Text to search for
  # @return [Boolean] True if text is found, false otherwise
  def pdf_contains_text?(file, text)
    path = file.respond_to?(:path) ? file.path : file
    
    begin
      content = File.binread(path)
      # This is a simple check - in real implementation you might want to use a PDF parser
      content.include?(text)
    rescue StandardError
      false
    end
  end
  
  # Creates a fixture file upload for a PDF
  # @param pdf_file [Tempfile] PDF file
  # @param content_type [String] Content type
  # @return [ActionDispatch::Http::UploadedFile] Fixture file upload
  def pdf_fixture_upload(pdf_file, content_type = "application/pdf")
    fixture_file_upload(pdf_file.path, content_type)
  end
  
  # RSpec shared examples for PDF upload tests
  # Usage: include_examples "pdf upload examples", your_upload_method
  def self.included(base)
    base.shared_examples "pdf upload examples" do |upload_method|
      let(:valid_pdf) { create_invoice_pdf }
      let(:empty_pdf) { create_empty_pdf }
      let(:large_pdf) { create_large_pdf(2) } # 2MB PDF
      let(:fake_pdf) { create_fake_pdf }
      let(:zero_byte_pdf) { create_zero_byte_pdf }
      
      it "accepts a valid PDF file" do
        result = instance_exec(valid_pdf, &upload_method)
        expect(result).to be_success
      end
      
      it "accepts an empty but valid PDF" do
        result = instance_exec(empty_pdf, &upload_method)
        expect(result).to be_success
      end
      
      it "rejects a non-PDF file with PDF extension" do
        result = instance_exec(fake_pdf, &upload_method)
        expect(result).not_to be_success
      end
      
      it "handles zero-byte files appropriately" do
        result = instance_exec(zero_byte_pdf, &upload_method)
        # The expected behavior depends on your application requirements
        # This test should be adjusted based on how you want to handle zero-byte files
        expect(result).to be_success
      end
      
      it "handles large PDF files" do
        result = instance_exec(large_pdf, &upload_method)
        expect(result).to be_success
      end
    end
  end
  
  private
  
  # Default options for invoice PDF generation
  def default_invoice_options
    {
      title: "INVOICE",
      invoice_number: "INV-#{Time.now.to_i}",
      date: Date.today.to_s,
      company_name: "Acme Corporation",
      contractor_name: "John Doe Consulting",
      line_items: [
        { description: "Development work", quantity: 40, rate: 100 },
        { description: "Design work", quantity: 10, rate: 120 }
      ],
      total_amount: 5200_00 # $5,200.00 in cents
    }
  end
  
  # Formats line items for PDF table
  def line_items_data(items)
    headers = [["Description", "Quantity", "Rate", "Amount"]]
    
    rows = items.map do |item|
      amount = item[:quantity] * item[:rate]
      [
        item[:description],
        item[:quantity].to_s,
        "$#{format("%.2f", item[:rate])}",
        "$#{format("%.2f", amount)}"
      ]
    end
    
    headers + rows
  end
  
  # Path to a dummy image for PDF testing
  def dummy_image_path
    Rails.root.join("spec", "fixtures", "files", "sample.jpg")
  end
end
