import { db, takeOrThrow } from "@test/db";
import { companiesFactory } from "@test/factories/companies";
import { companyContractorsFactory } from "@test/factories/companyContractors";
import { usersFactory } from "@test/factories/users";
import { fillDatePicker } from "@test/helpers";
import { login } from "@test/helpers/auth";
import { expect, test } from "@test/index";
import { subDays } from "date-fns";
import { desc, eq } from "drizzle-orm";
import path from "path";
import {
  companies,
  companyContractors,
  invoiceLineItems,
  invoices,
  users,
} from "@/db/schema";

test.describe("invoice PDF upload", () => {
  let company: typeof companies.$inferSelect;
  let contractorUser: typeof users.$inferSelect;
  let companyContractor: typeof companyContractors.$inferSelect;

  test.beforeEach(async () => {
    company = (
      await companiesFactory.createCompletedOnboarding({
        equityEnabled: true,
      })
    ).company;

    contractorUser = (
      await usersFactory.createWithBusinessEntity({
        zipCode: "22222",
        streetAddress: "1st St.",
      })
    ).user;

    companyContractor = (
      await companyContractorsFactory.create({
        companyId: company.id,
        userId: contractorUser.id,
        payRateInSubunits: 6000,
        equityPercentage: 0,
      })
    ).companyContractor;
  });

  test("can upload a PDF when creating an invoice", async ({ page }) => {
    await login({ page, user: contractorUser });
    await page.goto("/invoices/new");

    // Fill basic invoice details
    const invoiceNumber = "INV-PDF-001";
    await page.getByLabel("Invoice ID").fill(invoiceNumber);
    await fillDatePicker(page, "Invoice date", new Date());
    
    // Add a line item
    await page.getByLabel("Line item").fill("Development work");
    await page.getByLabel("Hours / Qty").fill("10");
    await page.getByLabel("Rate").fill("60");

    // Upload a PDF file
    const pdfPath = path.join(__dirname, "../../../samples/sample.pdf");
    await page.getByRole("button", { name: "Upload PDF" }).click();
    await page.locator('input[type="file"]').setInputFiles(pdfPath);
    
    // Verify the file appears in the UI
    await expect(page.getByText("sample.pdf")).toBeVisible();
    
    // Submit the invoice
    await page.getByRole("button", { name: "Send invoice" }).click();
    
    // Wait for redirect to invoice list
    await expect(page).toHaveURL("/invoices");
    
    // Verify the invoice was created with the PDF
    const createdInvoice = await takeOrThrow(
      db
        .select()
        .from(invoices)
        .where(eq(invoices.userId, contractorUser.id))
        .orderBy(desc(invoices.createdAt))
        .limit(1)
    );
    
    expect(createdInvoice.invoiceNumber).toBe(invoiceNumber);
    
    // Navigate to the invoice detail page
    await page.goto(`/invoices/${createdInvoice.externalId}`);
    
    // Verify the PDF is associated with the invoice
    await expect(page.getByText("Invoice PDF")).toBeVisible();
    await expect(page.getByRole("link", { name: /sample\.pdf/i })).toBeVisible();
  });

  test("shows error when uploading non-PDF file", async ({ page }) => {
    await login({ page, user: contractorUser });
    await page.goto("/invoices/new");

    // Fill basic invoice details
    await page.getByLabel("Invoice ID").fill("INV-PDF-002");
    await fillDatePicker(page, "Invoice date", new Date());
    
    // Add a line item
    await page.getByLabel("Line item").fill("Development work");
    await page.getByLabel("Hours / Qty").fill("10");
    await page.getByLabel("Rate").fill("60");

    // Try to upload a non-PDF file (using a JPG file)
    const jpgPath = path.join(__dirname, "../../../samples/sample.jpg");
    await page.getByRole("button", { name: "Upload PDF" }).click();
    await page.locator('input[type="file"]').setInputFiles(jpgPath);
    
    // Verify error message appears
    await expect(page.getByText("Only PDF files are allowed")).toBeVisible();
    
    // Verify the file is not shown in the UI
    await expect(page.getByText("sample.jpg")).not.toBeVisible();
  });

  test("can replace PDF with another PDF", async ({ page }) => {
    await login({ page, user: contractorUser });
    await page.goto("/invoices/new");

    // Fill basic invoice details
    await page.getByLabel("Invoice ID").fill("INV-PDF-003");
    await fillDatePicker(page, "Invoice date", new Date());
    
    // Add a line item
    await page.getByLabel("Line item").fill("Development work");
    await page.getByLabel("Hours / Qty").fill("10");
    await page.getByLabel("Rate").fill("60");

    // Upload first PDF file
    const firstPdfPath = path.join(__dirname, "../../../samples/sample.pdf");
    await page.getByRole("button", { name: "Upload PDF" }).click();
    await page.locator('input[type="file"]').setInputFiles(firstPdfPath);
    
    // Verify the first file appears
    await expect(page.getByText("sample.pdf")).toBeVisible();
    
    // Replace with second PDF file
    const secondPdfPath = path.join(__dirname, "../../../samples/invoice-template.pdf");
    await page.getByRole("button", { name: "Replace PDF" }).click();
    await page.locator('input[type="file"]').setInputFiles(secondPdfPath);
    
    // Verify the second file appears
    await expect(page.getByText("invoice-template.pdf")).toBeVisible();
    
    // Submit the invoice
    await page.getByRole("button", { name: "Send invoice" }).click();
    
    // Wait for redirect to invoice list
    await expect(page).toHaveURL("/invoices");
  });

  test("submits invoice successfully without PDF", async ({ page }) => {
    await login({ page, user: contractorUser });
    await page.goto("/invoices/new");

    // Fill basic invoice details
    const invoiceNumber = "INV-PDF-004";
    await page.getByLabel("Invoice ID").fill(invoiceNumber);
    await fillDatePicker(page, "Invoice date", new Date());
    
    // Add a line item
    await page.getByLabel("Line item").fill("Development work");
    await page.getByLabel("Hours / Qty").fill("10");
    await page.getByLabel("Rate").fill("60");
    
    // Submit without uploading a PDF
    await page.getByRole("button", { name: "Send invoice" }).click();
    
    // Wait for redirect to invoice list
    await expect(page).toHaveURL("/invoices");
    
    // Verify the invoice was created without PDF
    const createdInvoice = await takeOrThrow(
      db
        .select()
        .from(invoices)
        .where(eq(invoices.userId, contractorUser.id))
        .orderBy(desc(invoices.createdAt))
        .limit(1)
    );
    
    expect(createdInvoice.invoiceNumber).toBe(invoiceNumber);
  });
});
