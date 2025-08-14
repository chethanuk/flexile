# ===================================================
# Flexile Backend Test Makefile
# ===================================================
# Simple commands for running tests with API mocks
# No real credentials required!
#
# Usage:
#   make test         # Run all tests with mocks
#   make test-models  # Run model tests only
#   make help         # Show all commands
# ===================================================

# Default database connection for tests
DB_URL ?= postgresql://$(USER)@127.0.0.1:5432/flexile_test

# Test environment variables
TEST_ENV = RAILS_ENV=test \
           DATABASE_URL="$(DB_URL)" \
           USE_STRIPE_MOCK=true \
           USE_WISE_MOCK=true \
           WISE_PROFILE_ID=local_test \
           WISE_API_KEY=local_test

# Colors for better output
BLUE := \033[1;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
NC := \033[0m

.PHONY: help test test-models test-services test-controllers test-stripe test-wise verify-mocks clean

# Default target
help:
	@echo ""
	@echo "${BLUE}Flexile Backend Test Commands${NC}"
	@echo "========================================"
	@echo "${GREEN}make test${NC}           Run all tests with API mocks"
	@echo "${GREEN}make test-models${NC}    Run model tests only"
	@echo "${GREEN}make test-services${NC}  Run service tests only"
	@echo "${GREEN}make test-controllers${NC} Run controller tests only"
	@echo "${GREEN}make test-stripe${NC}    Run Stripe-specific tests"
	@echo "${GREEN}make test-wise${NC}      Run Wise-specific tests"
	@echo "${GREEN}make verify-mocks${NC}   Verify mock configuration"
	@echo "${GREEN}make clean${NC}          Stop stripe-mock server"
	@echo ""
	@echo "${YELLOW}Run a specific test:${NC}"
	@echo "  make test SPEC=path/to/spec.rb"
	@echo ""

# Run all tests with mocks
test:
ifdef SPEC
	@echo "Running specific test: ${SPEC}"
	@${TEST_ENV} bundle exec rake "test:with_mocks[${SPEC}]"
else
	@echo "Running all tests with mocks..."
	@${TEST_ENV} bundle exec rake test:with_mocks
endif

# Run model tests only
test-models:
	@echo "Running model tests with mocks..."
	@${TEST_ENV} bundle exec rake "test:with_mocks[spec/models]"

# Run service tests only
test-services:
	@echo "Running service tests with mocks..."
	@${TEST_ENV} bundle exec rake "test:with_mocks[spec/services]"

# Run controller tests only
test-controllers:
	@echo "Running controller tests with mocks..."
	@${TEST_ENV} bundle exec rake "test:with_mocks[spec/controllers]"

# Run Stripe-specific tests
test-stripe:
	@echo "Running Stripe-specific tests with mocks..."
	@${TEST_ENV} bundle exec rake "test:with_mocks[spec/models/company_stripe_account_spec.rb]"
	@${TEST_ENV} bundle exec rake "test:with_mocks[spec/services/stripe]"

# Run Wise-specific tests
test-wise:
	@echo "Running Wise-specific tests with mocks..."
	@${TEST_ENV} bundle exec rake "test:with_mocks[spec/models/wise_recipient_spec.rb]"
	@${TEST_ENV} bundle exec rake "test:with_mocks[spec/models/wise_credential_spec.rb]"

# Verify mock configuration
verify-mocks:
	@echo "Verifying mock configuration..."
	@${TEST_ENV} bundle exec rake test:verify_mocks

# Clean up resources
clean:
	@echo "Stopping stripe-mock server if running..."
	@-pkill -f "stripe-mock" || true
	@echo "Done!"
