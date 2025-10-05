# Homelab Infrastructure Articles

A comprehensive 10-article series on building a production-grade Kubernetes homelab using GitOps, Terraform, CNPG, and ArgoCD.

## Article Series Overview

Total: **6,089 lines** of in-depth technical content with real, working code examples.

### 1. [GitOps Disaster Recovery: How I Accidentally Deleted Production (And Recovered in 5 Minutes)](./01-gitops-disaster-recovery.md)
**434 lines | 12KB**

Real incident report: accidentally deleted all production applications with a grep command, and recovered in 5 minutes using GitOps principles.

**Key Topics:**
- Real production incident analysis
- GitOps recovery procedures
- Separation of data vs. compute
- Defensive scripting patterns
- kubectl recovery workflows

**Code Examples:**
- Safe deletion patterns
- Recovery commands
- Backup verification scripts

---

### 2. [CNPG Multi-Environment Database Strategy: One Cluster or Many?](./02-cnpg-multi-environment-strategy.md)
**591 lines | 15KB**

Architectural decisions for running PostgreSQL databases across dev, QA, and production environments using CloudNativePG.

**Key Topics:**
- Dedicated clusters per application
- Multi-environment resource allocation
- Cross-environment restore patterns
- Backup strategy per environment
- Service discovery and naming

**Code Examples:**
- Complete CNPG cluster configurations
- Kustomize base + overlay patterns
- Database connection strings
- Resource allocation by environment

---

### 3. [Kubernetes Resource Optimization: How I Freed 40% CPU by Deleting QA Without Losing My Work](./03-kubernetes-resource-optimization.md)
**617 lines | 15KB**

Dynamic environment lifecycle management to maximize homelab efficiency while maintaining flexibility.

**Key Topics:**
- On-demand environment creation
- GitOps-based recreation
- Resource allocation strategies
- Automated cleanup scripts
- Cost/benefit analysis

**Code Examples:**
- Safe QA deletion workflow
- Environment recreation scripts
- Resource monitoring
- Scheduled cleanup jobs

---

### 4. [The Hidden Cost of Kubernetes Health Checks: Debugging Readiness Probe Failures](./04-debugging-health-checks.md)
**606 lines | 17KB**

Deep dive into debugging pods stuck at 0/1 READY, with real-world commafeed readiness probe failure analysis.

**Key Topics:**
- Liveness vs. readiness vs. startup probes
- Systematic debugging process
- Common probe pitfalls
- Application-specific probe strategies
- Monitoring probe failures

**Code Examples:**
- Complete debugging workflow
- Probe configurations for various app types
- Testing probe endpoints
- Prometheus alerts for probe failures

---

### 5. [CNPG Backup and Restore Patterns: From Azure to Point-in-Time Recovery](./05-cnpg-backup-restore-patterns.md)
**751 lines | 18KB**

Complete guide to CNPG backup strategies using Azure Blob Storage, including automated backups, cross-environment restores, and disaster recovery testing.

**Key Topics:**
- Azure Blob Storage integration
- Scheduled backup configuration
- Point-in-time recovery
- Cross-environment restore (prod-to-qa)
- Backup testing procedures

**Code Examples:**
- Complete backup configurations
- Azure CLI commands
- Restore workflows
- Automated testing scripts
- Terraform Azure storage setup

---

### 6. [ArgoCD ApplicationSets: Auto-Discovering Apps Without Repetitive YAML](./06-argocd-applicationsets.md)
**516 lines | 11KB**

Managing dozens of applications across multiple environments with a single ApplicationSet using directory-based auto-discovery.

**Key Topics:**
- ApplicationSet generators
- Directory-based discovery patterns
- Template variables and naming
- Multi-environment patterns
- Troubleshooting auto-discovery

**Code Examples:**
- Complete ApplicationSet configurations
- Path pattern matching
- Label-based filtering
- Multiple ApplicationSet strategies

---

### 7. [Kustomize Overlays in Practice: Managing 5 Apps Across 3 Environments](./07-kustomize-overlays-practice.md)
**428 lines | 9KB**

Real-world Kustomize patterns from managing n8n, commafeed, linkding, listmonk, and wallabag across dev, QA, and production.

**Key Topics:**
- Base + overlay architecture
- Strategic merge vs. JSON patches
- Environment-specific configurations
- Common pitfalls and solutions
- DRY principles in action

**Code Examples:**
- Complete base configurations
- Production/QA/dev overlays
- Patch strategies
- Database host per environment
- Secret management per environment

---

### 8. [Zero-Downtime Database Migrations with CNPG: Upgrading from v1 to v3](./08-zero-downtime-database-migrations.md)
**453 lines | 11KB**

How to migrate PostgreSQL databases from v1 to v3 with zero downtime using CNPG's recovery features and blue-green deployment patterns.

**Key Topics:**
- Blue-green migration strategy
- Bootstrap from existing cluster
- Version upgrades (PostgreSQL 15 → 16)
- Adding high availability
- Rollback procedures

**Code Examples:**
- Complete migration workflow
- Cluster bootstrap configuration
- Data verification scripts
- Rollback procedures
- Migration checklist

---

### 9. [Terraform + ArgoCD: The Complete GitOps Stack for Kubernetes Infrastructure](./09-terraform-argocd-gitops-stack.md)
**901 lines | 22KB**

Combining Terraform's infrastructure provisioning with ArgoCD's application deployment for a complete, declarative Kubernetes platform.

**Key Topics:**
- Two-layer architecture (infrastructure vs. applications)
- Terraform module structure
- ArgoCD self-management
- The handoff between Terraform and ArgoCD
- Complete setup from scratch

**Code Examples:**
- Complete Terraform configurations
- Azure Key Vault module
- CNPG operator module
- ArgoCD module
- External Secrets module
- Bootstrap workflow
- Complete setup script

---

### 10. [External Secrets + CNPG: Automatic Database Credential Management and Rotation](./10-external-secrets-cnpg-rotation.md)
**792 lines | 19KB**

Integrating Azure Key Vault with Kubernetes using External Secrets Operator, eliminating hardcoded credentials and enabling automatic rotation.

**Key Topics:**
- External Secrets Operator setup
- Azure Key Vault integration
- ClusterSecretStore configuration
- ExternalSecret patterns
- Credential rotation strategies

**Code Examples:**
- Complete ESO setup with Terraform
- ClusterSecretStore configuration
- ExternalSecret for databases
- ExternalSecret for applications
- Rotation workflows
- Monitoring and troubleshooting

---

## Getting Started

### Prerequisites

- MicroK8s or similar Kubernetes cluster
- Azure subscription (for Key Vault and Storage)
- Terraform >= 1.5.0
- kubectl
- Azure CLI
- Git

### Quick Start

```bash
# Clone the repository
git clone https://github.com/aminrj/homelab-terraform-gitops-infra.git
cd homelab-terraform-gitops-infra

# Follow the articles in order:
# 1. Start with Article 9 (Terraform + ArgoCD) for infrastructure setup
# 2. Then Article 10 (External Secrets) for secret management
# 3. Article 2 (CNPG Multi-Environment) for database architecture
# 4. Article 5 (CNPG Backups) for backup strategy
# 5. Article 6 (ArgoCD ApplicationSets) for app auto-discovery
# 6. Article 7 (Kustomize Overlays) for configuration management
# 7. Article 3 (Resource Optimization) for efficient resource usage
# 8. Article 4 (Health Checks) for troubleshooting
# 9. Article 8 (Database Migrations) for upgrades
# 10. Article 1 (Disaster Recovery) for incident handling
```

## Architecture Overview

```
┌─────────────────────────────────────────────┐
│  Terraform (Infrastructure Layer)           │
│  ├─ Azure Key Vault                         │
│  ├─ Storage Accounts                        │
│  ├─ CNPG Operator                           │
│  ├─ External Secrets Operator               │
│  └─ ArgoCD                                  │
└──────────────┬──────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│  ArgoCD (Application Layer)                 │
│  ├─ Applications (auto-discovered from Git) │
│  ├─ Database Clusters (CNPG)                │
│  ├─ External Secrets                        │
│  └─ Configuration (Kustomize)               │
└─────────────────────────────────────────────┘
```

## Key Technologies

- **Kubernetes**: MicroK8s
- **GitOps**: ArgoCD with ApplicationSets
- **Configuration**: Kustomize
- **Infrastructure**: Terraform
- **Databases**: CloudNativePG (CNPG)
- **Secrets**: External Secrets Operator + Azure Key Vault
- **Backups**: Azure Blob Storage
- **Certificates**: Cert Manager + Let's Encrypt
- **Load Balancing**: MetalLB
- **DNS**: External DNS

## Applications Covered

- **n8n**: Workflow automation
- **Commafeed**: RSS reader
- **Linkding**: Bookmark manager
- **Listmonk**: Newsletter manager
- **Wallabag**: Read-it-later service

Each application demonstrates:
- Multi-environment deployment (dev/qa/prod)
- Dedicated PostgreSQL cluster
- External Secrets integration
- Automated backups to Azure
- Kustomize-based configuration
- ArgoCD auto-discovery

## Repository Structure

```
homelab-terraform-gitops-infra/
├── articles/           # This article series
├── environments/       # Terraform root modules (prod, qa, dev)
├── modules/           # Reusable Terraform modules
├── argocd/            # ArgoCD ApplicationSets (managed by ArgoCD)
├── apps/              # Applications (managed by ArgoCD)
├── databases/         # CNPG clusters (managed by ArgoCD)
└── infrastructure/    # Core infra configs (managed by ArgoCD)
```

## Learning Path

### Beginner Track
1. Article 9 - Infrastructure setup
2. Article 6 - Application deployment
3. Article 7 - Configuration management

### Intermediate Track
4. Article 2 - Database architecture
5. Article 10 - Secret management
6. Article 5 - Backup strategies

### Advanced Track
7. Article 8 - Zero-downtime migrations
8. Article 3 - Resource optimization
9. Article 4 - Troubleshooting
10. Article 1 - Disaster recovery

## Real-World Value

These articles solve actual problems encountered while building a production-grade homelab:

- ✅ **No secrets in Git** - External Secrets Operator
- ✅ **Automatic backups** - CNPG + Azure Storage
- ✅ **Zero-downtime migrations** - Blue-green database upgrades
- ✅ **Self-service deployment** - ArgoCD ApplicationSets
- ✅ **Resource efficiency** - On-demand environments
- ✅ **Quick recovery** - GitOps disaster recovery
- ✅ **Multi-environment** - Kustomize overlays
- ✅ **Infrastructure as Code** - Terraform modules

## Contributing

Found an issue or have an improvement? Feel free to open a PR or issue at:
https://github.com/aminrj/homelab-terraform-gitops-infra

## Author

Amine Raji
- Website: https://aminrj.com
- GitHub: https://github.com/aminrj

## License

All code examples in these articles are MIT licensed. Feel free to use them in your own homelab!

---

*Last updated: October 2024*
*Total article count: 10*
*Total lines of code/content: 6,089*
