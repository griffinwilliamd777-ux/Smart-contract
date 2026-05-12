Signal Factory is a modular, production-ready pipeline for generating, analyzing, pricing, and distributing market signals. It integrates AI-driven Overseer logic, Human Intelligence Amplification (HIA), and a central Vault for storage, auditing, and distribution. The system is fully deployable on Railway, scalable, and secure.
Table of Contents
Features
Architecture
Services
Queue & Storage
Dashboard
Installation
Deployment on Railway
Environment Variables
Testing
License
Features
Full modular pipeline: Data Miner → Intake → Categorization → Assembly → Pricing → Overseer → Vault → Distribution
Overseer Brain API: AI-powered evaluation and rarity classification
Human Intelligence Amplifier (HIA): Human override for elite signals
Vault & Distribution: Central storage, audit logging, API feed, dashboard, private feeds
Signal Classification: Common, Rare, Elite, with tiered pricing
Queue-Based Decoupling: Redis ensures scalability and fault tolerance
Dashboard: Next.js interface for monitoring, analytics, and elite signal management
Railway Ready: Workers and static deployments pre-configured
Architecture
Copy code

[Data Miners / Scrapers] 
          ↓
[Signal Intake API] → Redis Queue
          ↓
[Categorization Agent] → Redis Queue
          ↓
[Signal Assembly Agent] → Redis Queue
          ↓
[Pricing Agent] → Redis Queue
          ↓
[Overseer Brain API] → Vault
          ↓
 ┌───────────────┬─────────────┬───────────────┐
 │               │             │               │
[API Feed]   [Dashboard]   [Private Feeds]
Services
Intake API: Receives raw signals and pushes them to the queue
Categorization Agent: Classifies and tags signals
Assembly Agent: Creates candidate signals with preliminary rarity, strength, and confidence
Pricing Agent: Calculates price, tier, and packaging
Overseer Brain API: Approves/rejects signals, integrates HIA, generates audit logs
Vault API: Stores signals, audit logs, and provides API feed
Queue & Storage
Redis: Queueing between all agents
PostgreSQL (Vault): Stores all approved signals, history, audit, and performance metrics
Dashboard
Built with Next.js
Provides:
Signal monitoring
Elite signal human approval (HIA)
Analytics & metrics
Connects to Overseer API and Vault API
Installation
Copy code
Bash
# Clone the repository
git clone https://github.com/<your-username>/signal-factory.git
cd signal-factory

# Install dependencies for each service
cd services/intake_api && pip install -r requirements.txt
cd ../categorization_agent && pip install -r requirements.txt
...
cd ../../dashboard && npm install
Deployment on Railway
Create a Railway project
Link GitHub repository
Add PostgreSQL & Redis add-ons
Set environment variables (see below)
Deploy each service as a worker
Deploy the Dashboard as a static deployment
Seed mock signals:
Copy code
Bash
cd scripts
python seed_mock_data.py
Environment Variables
Variable
Description
REDIS_URL
Redis connection URI
DB_URI
PostgreSQL connection URI
AI_API_KEY
API key for Overseer reasoning engine
VAULT_SECRET
Vault authorization secret
Testing
Unit test each service individually
End-to-end test pipeline:
Intake → Categorization → Assembly → Pricing → Overseer → Vault → Dashboard/API
Seed mock signals to validate flow
Verify elite signal human override
License
Proprietary / Private (recommended for your system)
All rights reserved by Griffin Vitalogy
