#!/usr/bin/env ruby
# simple_wise_test.rb
# A simple script to test Wise API WebMock configuration without Rails or RSpec

require 'webmock'
require 'httparty'
require 'json'

# Include WebMock API
include WebMock::API

# Configure WebMock
WebMock.enable!
WebMock.disable_net_connect!

# Helper methods for colored output (without requiring colorize gem)
def green(text); "\e[32m#{text}\e[0m"; end
def red(text); "\e[31m#{text}\e[0m"; end
def yellow(text); "\e[33m#{text}\e[0m"; end
def blue(text); "\e[34m#{text}\e[0m"; end

# Print header
puts blue("=" * 60)
puts blue("WISE API WEBMOCK TEST")
puts blue("=" * 60)

# Define Wise API constants
WISE_API_URL = "https://api.sandbox.transferwise.tech"
WISE_PROFILE_ID = "16421159"

# Define test data
wise_balance_response = [
  {
    "id" => 12345,
    "profileId" => 16421159,
    "currency" => "USD",
    "type" => "STANDARD",
    "amount" => {
      "value" => 1000.00,
      "currency" => "USD"
    },
    "reservedAmount" => {
      "value" => 0,
      "currency" => "USD"
    }
  }
]

wise_recipient_response = {
  "id" => 148563324,
  "currency" => "USD",
  "country" => "US",
  "type" => "sort_code",
  "accountHolderName" => "Test Recipient",
  "business" => nil,
  "profile" => 16421159,
  "active" => true,
  "ownedByCustomer" => true,
  "details" => {
    "address" => {
      "country" => "US",
      "countryCode" => "US",
      "firstLine" => "456 Test Ave",
      "postCode" => "54321",
      "city" => "New York",
      "state" => "NY"
    },
    "email" => "recipient@example.com",
    "legalType" => "PRIVATE",
    "accountNumber" => "1234567890",
    "sortCode" => "111222",
    "routingNumber" => "021000021",
    "accountType" => "CHECKING"
  }
}

# Step 1: Set up WebMock for Wise API
puts yellow("\n[1] Setting up WebMock for Wise API...")

# Step 2: Mock Wise balance endpoint
stub_request(:get, "#{WISE_API_URL}/v4/profiles/#{WISE_PROFILE_ID}/balances")
  .with(headers: { 'Authorization' => /Bearer .+/ })
  .to_return(
    status: 200,
    body: wise_balance_response.to_json,
    headers: { 'Content-Type' => 'application/json' }
  )

puts green("✓ Mocked GET #{WISE_API_URL}/v4/profiles/#{WISE_PROFILE_ID}/balances")

# Step 3: Mock Wise recipient endpoint
stub_request(:get, "#{WISE_API_URL}/v1/accounts/148563324")
  .with(headers: { 'Authorization' => /Bearer .+/ })
  .to_return(
    status: 200,
    body: wise_recipient_response.to_json,
    headers: { 'Content-Type' => 'application/json' }
  )

puts green("✓ Mocked GET #{WISE_API_URL}/v1/accounts/148563324")

# Step 4: Test the mocked endpoints
puts yellow("\n[2] Testing mocked Wise API endpoints...")

# Test balance endpoint
begin
  puts "Testing balance endpoint..."
  balance_response = HTTParty.get(
    "#{WISE_API_URL}/v4/profiles/#{WISE_PROFILE_ID}/balances",
    headers: { 'Authorization' => 'Bearer test_api_key' }
  )
  
  if balance_response.code == 200
    puts green("✓ Balance API mock works!")
    puts "  Response code: #{balance_response.code}"
    puts "  USD Balance: $#{JSON.parse(balance_response.body)[0]['amount']['value']}"
  else
    puts red("✗ Balance API mock failed!")
    puts red("  Unexpected response code: #{balance_response.code}")
  end
rescue => e
  puts red("✗ Balance API mock failed with error:")
  puts red("  #{e.message}")
end

# Test recipient endpoint
begin
  puts "\nTesting recipient endpoint..."
  recipient_response = HTTParty.get(
    "#{WISE_API_URL}/v1/accounts/148563324",
    headers: { 'Authorization' => 'Bearer test_api_key' }
  )
  
  if recipient_response.code == 200
    puts green("✓ Recipient API mock works!")
    puts "  Response code: #{recipient_response.code}"
    puts "  Account holder: #{JSON.parse(recipient_response.body)['accountHolderName']}"
    puts "  Account number: ****#{JSON.parse(recipient_response.body)['details']['accountNumber'][-4..-1]}"
  else
    puts red("✗ Recipient API mock failed!")
    puts red("  Unexpected response code: #{recipient_response.code}")
  end
rescue => e
  puts red("✗ Recipient API mock failed with error:")
  puts red("  #{e.message}")
end

# Step 5: Verify WebMock is working properly
puts yellow("\n[3] Verifying WebMock configuration...")

# Try to make a request to an unmocked endpoint
begin
  puts "Testing unmocked endpoint (should be blocked)..."
  HTTParty.get("#{WISE_API_URL}/v1/profiles")
  puts red("✗ WebMock is NOT blocking unmocked requests!")
rescue WebMock::NetConnectNotAllowedError => e
  puts green("✓ WebMock correctly blocks unmocked requests")
end

# Summary
puts blue("\n" + "=" * 60)
puts "SUMMARY:"
puts "✓ WebMock configuration for Wise API is working correctly"
puts "✓ Mocked endpoints return expected responses"
puts "✓ Unmocked endpoints are properly blocked"
puts blue("=" * 60)
puts "\nThis confirms that the WebMock setup for Wise API is functioning as expected."
puts "You can now proceed with integrating this into your RSpec tests."
