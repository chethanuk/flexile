#!/usr/bin/env ruby
# test_mocks_verification.rb
# A standalone script to verify Stripe and Wise API mocking configurations

require 'bundler/setup'
require 'webmock'
require 'stripe'
require 'json'
require 'httparty'
require 'colorize'

# Include WebMock
include WebMock::API

# Configure WebMock to allow real connections to localhost
WebMock.disable_net_connect!(allow_localhost: true)

# Helper method for printing sections
def print_section(title)
  puts "\n#{'=' * 80}".light_blue
  puts "# #{title}".light_blue
  puts "#{'=' * 80}".light_blue
end

# Helper method for printing results
def print_result(test_name, success, message = nil)
  if success
    puts "✅ #{test_name}".green
  else
    puts "❌ #{test_name}".red
    puts "   #{message}".red if message
  end
end

# Helper method to print JSON responses
def print_json(title, json)
  puts "\n#{title}:".yellow
  puts JSON.pretty_generate(json)
end

print_section("MOCK VERIFICATION SCRIPT")
puts "This script verifies that Stripe and Wise API mocking is configured correctly."
puts "Running tests outside of RSpec to diagnose any configuration issues."

# Set environment variables
ENV['USE_STRIPE_MOCK'] = 'true'
ENV['USE_WISE_MOCK'] = 'true'
ENV['STRIPE_MOCK_HOST'] = 'localhost'
ENV['STRIPE_MOCK_PORT'] = '12111'
ENV['STRIPE_MOCK_PROTOCOL'] = 'http'
ENV['WISE_API_BASE'] = 'https://api.sandbox.transferwise.tech'

print_section("ENVIRONMENT VARIABLES")
puts "USE_STRIPE_MOCK: #{ENV['USE_STRIPE_MOCK']}"
puts "USE_WISE_MOCK: #{ENV['USE_WISE_MOCK']}"
puts "STRIPE_MOCK_HOST: #{ENV['STRIPE_MOCK_HOST']}"
puts "STRIPE_MOCK_PORT: #{ENV['STRIPE_MOCK_PORT']}"
puts "STRIPE_MOCK_PROTOCOL: #{ENV['STRIPE_MOCK_PROTOCOL']}"
puts "WISE_API_BASE: #{ENV['WISE_API_BASE']}"

# Test if stripe-mock is running
print_section("CHECKING STRIPE-MOCK SERVER")
begin
  stripe_mock_url = "http://#{ENV['STRIPE_MOCK_HOST']}:#{ENV['STRIPE_MOCK_PORT']}/v1/customers"
  puts "Testing connection to stripe-mock at: #{stripe_mock_url}"
  
  # Allow real connection to stripe-mock
  WebMock.disable_net_connect!(allow: ["#{ENV['STRIPE_MOCK_HOST']}:#{ENV['STRIPE_MOCK_PORT']}"])
  
  # Try to connect to stripe-mock
  response = HTTParty.get(
    stripe_mock_url,
    headers: { 'Authorization' => 'Bearer sk_test_mock' }
  )
  
  if response.code == 200
    print_result("stripe-mock server is running", true)
    puts "Response code: #{response.code}"
  else
    print_result("stripe-mock server connection", false, "Unexpected response code: #{response.code}")
  end
rescue => e
  print_result("stripe-mock server connection", false, e.message)
  puts "\nMake sure stripe-mock is running with:"
  puts "  docker run --rm -d -p 12111-12112:12111-12112 stripe/stripe-mock:latest"
  puts "  or"
  puts "  stripe-mock -http-port 12111 -https-port 12112"
end

# Re-enable WebMock to block all real connections
WebMock.disable_net_connect!(allow_localhost: true)

# Define mock data for Wise API
print_section("WISE API MOCKING")
puts "Setting up WebMock stubs for Wise API..."

# Mock Wise API data
WISE_API_URL = "https://api.sandbox.transferwise.tech"
WISE_PROFILE_ID = "16421159"
WISE_TEST_DATA = {
  balance: {
    id: 12345,
    profileId: 16421159,
    currency: "USD",
    type: "STANDARD",
    amount: {
      value: 1000.00,
      currency: "USD"
    }
  },
  recipient: {
    id: 148563324,
    currency: "USD",
    country: "US",
    type: "sort_code",
    accountHolderName: "Test Recipient",
    details: {
      accountNumber: "1234567890",
      sortCode: "111222",
      routingNumber: "021000021"
    }
  }
}

# Mock Wise balance endpoint
stub_request(:get, "#{WISE_API_URL}/v4/profiles/#{WISE_PROFILE_ID}/balances")
  .to_return(
    status: 200,
    body: [WISE_TEST_DATA[:balance]].to_json,
    headers: { 'Content-Type' => 'application/json' }
  )

# Mock Wise recipient endpoint
stub_request(:get, "#{WISE_API_URL}/v1/accounts/148563324")
  .to_return(
    status: 200,
    body: WISE_TEST_DATA[:recipient].to_json,
    headers: { 'Content-Type' => 'application/json' }
  )

# Test Wise API mocking
puts "Testing Wise API mocks..."

# Test balance endpoint
begin
  balance_response = HTTParty.get(
    "#{WISE_API_URL}/v4/profiles/#{WISE_PROFILE_ID}/balances",
    headers: { 'Authorization' => 'Bearer test_api_key' }
  )
  
  if balance_response.code == 200
    print_result("Wise balance API mock", true)
    print_json("Balance response", JSON.parse(balance_response.body))
  else
    print_result("Wise balance API mock", false, "Unexpected response code: #{balance_response.code}")
  end
rescue => e
  print_result("Wise balance API mock", false, e.message)
end

# Test recipient endpoint
begin
  recipient_response = HTTParty.get(
    "#{WISE_API_URL}/v1/accounts/148563324",
    headers: { 'Authorization' => 'Bearer test_api_key' }
  )
  
  if recipient_response.code == 200
    print_result("Wise recipient API mock", true)
    print_json("Recipient response", JSON.parse(recipient_response.body))
  else
    print_result("Wise recipient API mock", false, "Unexpected response code: #{recipient_response.code}")
  end
rescue => e
  print_result("Wise recipient API mock", false, e.message)
end

# Define mock data for Stripe API
print_section("STRIPE API MOCKING")
puts "Setting up WebMock stubs for Stripe API..."

# Configure Stripe to use our mock server
Stripe.api_base = "http://#{ENV['STRIPE_MOCK_HOST']}:#{ENV['STRIPE_MOCK_PORT']}"
Stripe.api_key = "sk_test_mock"

puts "Stripe configured to use: #{Stripe.api_base}"

# Define Stripe mock data
STRIPE_TEST_DATA = {
  payment_methods: {
    us_bank_account: {
      id: "pm_test_us_bank_account",
      object: "payment_method",
      type: "us_bank_account",
      us_bank_account: {
        account_holder_type: "individual",
        account_type: "checking",
        bank_name: "STRIPE TEST BANK",
        fingerprint: "FFDMA0jJDFjDf0aS",
        last4: "6789",
        routing_number: "110000000"
      }
    }
  },
  setup_intents: {
    succeeded: {
      id: "seti_mock_succeeded",
      object: "setup_intent",
      client_secret: "seti_mock_succeeded_secret_test",
      status: "succeeded",
      payment_method: "pm_test_us_bank_account"
    }
  }
}

# Mock Stripe setup intent endpoint
stub_request(:get, "#{Stripe.api_base}/v1/setup_intents/seti_mock_succeeded")
  .with(headers: { 'Authorization' => 'Bearer sk_test_mock' })
  .to_return(
    status: 200,
    body: STRIPE_TEST_DATA[:setup_intents][:succeeded].to_json,
    headers: { 'Content-Type' => 'application/json' }
  )

# Mock Stripe payment method endpoint
stub_request(:get, "#{Stripe.api_base}/v1/payment_methods/pm_test_us_bank_account")
  .with(headers: { 'Authorization' => 'Bearer sk_test_mock' })
  .to_return(
    status: 200,
    body: STRIPE_TEST_DATA[:payment_methods][:us_bank_account].to_json,
    headers: { 'Content-Type' => 'application/json' }
  )

# Test Stripe API mocking
puts "Testing Stripe API mocks..."

# Test setup intent retrieval
begin
  setup_intent = HTTParty.get(
    "#{Stripe.api_base}/v1/setup_intents/seti_mock_succeeded",
    headers: { 'Authorization' => 'Bearer sk_test_mock' }
  )
  
  if setup_intent.code == 200
    print_result("Stripe setup intent mock", true)
    print_json("Setup intent response", JSON.parse(setup_intent.body))
  else
    print_result("Stripe setup intent mock", false, "Unexpected response code: #{setup_intent.code}")
  end
rescue => e
  print_result("Stripe setup intent mock", false, e.message)
end

# Test payment method retrieval
begin
  payment_method = HTTParty.get(
    "#{Stripe.api_base}/v1/payment_methods/pm_test_us_bank_account",
    headers: { 'Authorization' => 'Bearer sk_test_mock' }
  )
  
  if payment_method.code == 200
    print_result("Stripe payment method mock", true)
    print_json("Payment method response", JSON.parse(payment_method.body))
  else
    print_result("Stripe payment method mock", false, "Unexpected response code: #{payment_method.code}")
  end
rescue => e
  print_result("Stripe payment method mock", false, e.message)
end

print_section("VERIFICATION SUMMARY")
puts "This script has verified the basic configuration of Stripe and Wise API mocking."
puts "If all tests passed, your mock setup should work correctly with RSpec."
puts "If any tests failed, check the error messages and fix the configuration."
puts "\nNext steps:"
puts "1. Run specific tests with: bin/test-with-local-stripe-mock spec/models/company_stripe_account_spec.rb"
puts "2. Run specific tests with: bin/test-with-local-stripe-mock spec/models/wise_recipient_spec.rb"
puts "3. Run all tests with: bin/test-with-local-stripe-mock"
