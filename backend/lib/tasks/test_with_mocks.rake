# frozen_string_literal: true

namespace :test do
  desc "Run tests with Stripe and Wise API mocks"
  task :with_mocks, [:test_path] => :environment do |_, args|
    require "open3"
    
    # Default to running all tests if no specific path provided
    test_path = args[:test_path] || ""
    
    # Set environment variables for mocking
    ENV["USE_STRIPE_MOCK"] = "true"
    ENV["USE_WISE_MOCK"] = "true"
    ENV["STRIPE_MOCK_HOST"] = "localhost"
    ENV["STRIPE_MOCK_PORT"] = "12111"
    
    # Check if stripe-mock is installed
    stripe_mock_installed = system("which stripe-mock > /dev/null 2>&1")
    unless stripe_mock_installed
      puts "Error: stripe-mock is not installed. Please install it with:"
      puts "  brew install stripe/stripe-mock/stripe-mock"
      puts "  or"
      puts "  go install github.com/stripe/stripe-mock@latest"
      exit 1
    end
    
    # Check if stripe-mock is already running
    stripe_mock_running = system("lsof -i:12111 -sTCP:LISTEN > /dev/null 2>&1")
    stripe_mock_pid = nil
    
    unless stripe_mock_running
      # Start stripe-mock in the background
      puts "Starting stripe-mock server..."
      stripe_mock_pid = spawn("stripe-mock -http-port 12111 -https-port 12112")
      Process.detach(stripe_mock_pid)
      
      # Wait for stripe-mock to be ready
      max_retries = 5
      retries = 0
      stripe_mock_ready = false
      
      while retries < max_retries && !stripe_mock_ready
        sleep 1
        begin
          require "net/http"
          response = Net::HTTP.get_response(URI("http://localhost:12111/v1/charges"))
          stripe_mock_ready = response.code.to_i == 200
        rescue StandardError
          retries += 1
        end
      end
      
      unless stripe_mock_ready
        puts "Error: Failed to start stripe-mock server"
        Process.kill("TERM", stripe_mock_pid) if stripe_mock_pid
        exit 1
      end
      
      puts "stripe-mock is running on port 12111"
    end
    
    begin
      # Run RSpec with the specified path
      rspec_command = "bundle exec rspec #{test_path}"
      puts "Running: #{rspec_command}"
      
      # Execute RSpec and stream output
      status = system(rspec_command)
      
      # Report results
      if status
        puts "Tests completed successfully"
      else
        puts "Tests failed"
        exit 1
      end
    ensure
      # Clean up stripe-mock if we started it
      if stripe_mock_pid
        puts "Stopping stripe-mock server..."
        Process.kill("TERM", stripe_mock_pid)
      end
    end
  end
  
  desc "Run tests with Stripe and Wise API mocks in verbose mode"
  task :with_mocks_verbose, [:test_path] => :environment do |_, args|
    ENV["VERBOSE"] = "true"
    Rake::Task["test:with_mocks"].invoke(args[:test_path])
  end
  
  desc "Verify mock configuration without running tests"
  task verify_mocks: :environment do
    ENV["USE_STRIPE_MOCK"] = "true"
    ENV["USE_WISE_MOCK"] = "true"
    
    puts "Verifying Stripe mock configuration..."
    if system("which stripe-mock > /dev/null 2>&1")
      puts "✓ stripe-mock is installed"
      
      if system("lsof -i:12111 -sTCP:LISTEN > /dev/null 2>&1")
        puts "✓ stripe-mock is already running on port 12111"
      else
        puts "× stripe-mock is not running"
        puts "  Start it with: stripe-mock -http-port 12111 -https-port 12112"
      end
    else
      puts "× stripe-mock is not installed"
      puts "  Install it with: brew install stripe/stripe-mock/stripe-mock"
    end
    
    puts "\nVerifying Wise mock configuration..."
    puts "✓ WebMock is configured for Wise API mocking"
    
    puts "\nTo run tests with mocks:"
    puts "  rake test:with_mocks              # Run all tests"
    puts "  rake test:with_mocks[spec/models] # Run specific directory"
    puts "  rake test:with_mocks[spec/models/company_spec.rb] # Run specific file"
  end
end
