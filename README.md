# Banking API

A Ruby on Rails API application for managing credit card transaction data with advanced filtering and credit-debit matching capabilities.

## Overview

This application provides a RESTful API and GraphQL interface for tracking and analyzing credit card transactions. It supports categorizing transactions as debits or credits, matching debits with corresponding credits, and adding notes for transaction annotation.

## Features

- **Transaction Management**: Track credit card transactions with debit/credit classification
- **Credit-Debit Matching**: Associate credit transactions with their corresponding debits
- **Transaction Filtering**: Filter transactions by type (debits, credits, outstanding debits, matched debits)
- **Notes System**: Add annotations to transactions for better record-keeping
- **GraphQL API**: Modern GraphQL interface alongside REST endpoints
- **Duplicate Prevention**: Unique constraints prevent duplicate transactions

## Tech Stack

- **Ruby**: 3.4.5
- **Rails**: 7.2.2.2 (API mode)
- **Database**: PostgreSQL
- **GraphQL**: GraphQL with GraphQL Batch for efficient queries
- **Serialization**: JSONAPI Serializer
- **Testing**: RSpec
- **Deployment**: Docker with Kamal

## Database Schema

### Credit Card Transactions
- `id`: Primary key
- `tx_date`: Transaction date
- `details`: Transaction description
- `debit`: Debit amount (null for credit transactions)
- `credit`: Credit amount (null for debit transactions)
- `card_number`: Associated card number
- Unique constraints prevent duplicate transactions

### Credits-Debits Matching
- Links credit transactions to their corresponding debits
- One-to-one relationship with unique indexes

### Notes
- Allows adding annotations to transactions
- One-to-one relationship with transactions

## API Endpoints

### REST API
- `GET /credit_card_transactions` - List all transactions (last 1000)
- `GET /credit_card_transactions/debits` - List debit transactions
- `GET /credit_card_transactions/debits_outstanding` - List unmatched debits
- `GET /credit_card_transactions/debits_with_credits` - List matched debits with credits
- `GET /up` - Health check endpoint

### GraphQL API
- `POST /graphql` - GraphQL endpoint for queries and mutations

## Setup

### Prerequisites
- Ruby 3.4.5
- PostgreSQL
- Docker (for containerized deployment)

### Development Setup
1. Clone the repository
2. Install dependencies: `bundle install`
3. Setup database: `rails db:create db:migrate db:seed`
4. Start server: `rails server`

### Docker Deployment
1. Build image: `docker build -t banking-api .`
2. Run container with required environment variables:
   ```bash
   docker run -d -p 3000:3000 \
     -e POSTGRES_USER=your_user \
     -e POSTGRES_PASSWORD=your_password \
     -e POSTGRES_DB=banking_production \
     -e DB_HOST=your_db_host \
     banking-api
   ```

### Environment Variables (Production)
- `DB_HOST`: Database host
- `POSTGRES_USER`: Database username
- `POSTGRES_PASSWORD`: Database password
- `POSTGRES_DB`: Database name
- `RAILS_MASTER_KEY`: Rails master key for credentials

## Testing

Run the test suite:
```bash
bundle exec rspec
```

## Key Models

### CreditCardTransaction
- Main transaction model with debit/credit classification
- Supports scopes for filtering by transaction type
- Includes methods for determining transaction nature

### DebitSpecificCredit
- Junction model for credit-debit relationships
- Ensures one-to-one mapping between credits and debits

### Note
- Annotation system for transactions
- Optional additional details for record-keeping

## Development Notes

- The application runs in API-only mode (no views/assets)
- Uses PostgreSQL-specific features (unique partial indexes)
- Includes database seeding functionality
- Configured for production deployment with Docker and Kamal