# Rapyd Sentinel — Split Architecture POC

Proof-of-concept for the Sentinel split architecture: two isolated AWS VPCs, one EKS cluster per VPC, private cross-VPC communication over VPC Peering, and a fully automated GitHub Actions pipeline (no local `terraform apply`).

```
                                  Internet
                                     │
                              ┌──────▼──────┐
                              │  Public ELB │   (vpc-gateway public subnets)
                              └──────┬──────┘
        vpc-gateway (10.0.0.0/16)    │
        ┌────────────────────────────▼────────────────────────┐
        │  eks-gateway (private subnets, 2 AZs)               │
        │  └─ nginx reverse proxy (sentinel-gateway ns)       │
        └────────────────────────────┬────────────────────────┘
                                     │  VPC Peering (pcx)
                                     │  private routing only
        vpc-backend (10.1.0.0/16)    │
        ┌────────────────────────────▼────────────────────────┐
        │  Internal ELB (source-restricted to 10.0.0.0/16)    │
        │  eks-backend (private subnets, 2 AZs)               │
        │  └─ http-echo "Hello from backend"                  │
        │     (sentinel-backend ns, NetworkPolicy enforced)   │
        └─────────────────────────────────────────────────────┘
```

## Repository layout

```
.github/workflows/deploy.yml   CI/CD pipeline (Terraform + K8s + e2e test)
terraform/
  main.tf                      Composition of the modules
  backend.tf                   S3 remote state (native S3 locking)
  modules/
    networking/                VPC, subnets, IGW, NAT, route tables
    peering/                   VPC Peering + cross-VPC routes + DNS resolution
    iam/                       EKS cluster/node roles (eks-* prefix only)
    eks/                       EKS cluster, VPC CNI addon, managed node group
k8s/
  backend/                     Namespace, Deployment, internal LB Service, NetworkPolicy
  gateway/                     Namespace, nginx Deployment, ConfigMap template, public LB Service
```

## How to run

### 0. One-time bootstrap (outside Terraform)

The only manual step is creating the state bucket (chicken-and-egg: the backend cannot store its own state):

```bash
aws s3 mb s3://sentinel-tfstate-darwhas --region eu-west-2
aws s3api put-bucket-versioning --bucket sentinel-tfstate-darwhas \
  --versioning-configuration Status=Enabled
```

> S3 bucket names are global; if taken, change the name here and in `terraform/backend.tf`.

### 1. Clone and configure GitHub

```bash
git clone https://github.com/<your-user>/rapyd-sentinel.git
```

In the GitHub repo: **Settings → Secrets and variables → Actions**, add:

| Secret | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | provided challenge credentials |
| `AWS_SECRET_ACCESS_KEY` | provided challenge credentials |

### 2. Push to `main`

```bash
git push origin main
```

That's it. The pipeline does everything else:

1. **terraform job** — `fmt -check` → `init` → `validate` → `tflint` → `plan` → `apply` (apply only on push to `main`; PRs run plan only).
2. **deploy-apps job** — `kubeconform` validation → server-side `kubectl apply --dry-run` → deploy backend → wait for internal ELB DNS → render the proxy ConfigMap with that DNS (`envsubst`, restricted to `${BACKEND_ENDPOINT}` so nginx runtime variables survive) → deploy the gateway proxy → wait for the public ELB → **end-to-end curl test** asserting the public URL returns `Hello from backend`.

The public URL is printed in the *Wait for public ELB* step of the workflow logs.

## Networking design

| Item | Decision |
|---|---|
| VPCs | `vpc-gateway` 10.0.0.0/16, `vpc-backend` 10.1.0.0/16 — non-overlapping, required for peering |
| Subnets | Per VPC: 2 private (nodes) + 2 public (NAT GW / ELB ENIs only) across `eu-west-2a/b` |
| Egress | 1 NAT Gateway per VPC (cost trade-off; production: one per AZ for HA) |
| Cross-VPC | VPC Peering with `auto_accept` (same account) + routes in all route tables both ways + remote DNS resolution enabled so the internal ELB name resolves from vpc-gateway |
| Public exposure | **Zero public EC2 instances.** Only ELB ENIs and NAT GWs live in public subnets; `map_public_ip_on_launch = false` everywhere |

**Why Peering over Transit Gateway:** two VPCs, one relationship, same account/region. TGW adds ~$0.05/h + per-GB processing and value only appears at 3+ VPCs or multi-account. Documented as the natural evolution path.

## How the proxy reaches the backend

1. The backend Service is `type: LoadBalancer` with the `aws-load-balancer-internal: "true"` annotation → AWS provisions an **internal ELB** in vpc-backend's private subnets (found via the `kubernetes.io/role/internal-elb` subnet tag).
2. `loadBalancerSourceRanges: [10.0.0.0/16]` restricts the ELB's security group so **only the gateway VPC** can connect.
3. The CI pipeline reads the ELB's DNS name and injects it into the nginx ConfigMap (`proxy_pass http://<internal-elb-dns>`).
4. nginx in eks-gateway resolves that name (peering has `allow_remote_vpc_dns_resolution = true`) to private 10.1.x.x IPs and traffic flows over the peering — never over the internet.

*Known limitation:* nginx resolves `proxy_pass` DNS at startup and caches it. Acceptable for a POC (the pipeline restarts the proxy after rendering the config); production would use nginx `resolver` with a variable upstream, an ingress controller, or a service mesh.

## Security model

- **IAM least privilege / approved prefixes:** all four roles are created by the `iam` module and follow the mandated `eks-` prefix (`eks-gateway-cluster-role`, `eks-gateway-node-role`, `eks-backend-*`). A Terraform `validation` block rejects any cluster name that would break the prefix rule. No other roles are created or passed.
- **Defense in depth for the backend (3 layers):**
  1. *ELB SG* — `loadBalancerSourceRanges` allows only 10.0.0.0/16.
  2. *Cluster SG* — explicit Terraform rules allow only ports 80 and the NodePort range (30000–32768) from the gateway VPC CIDR.
  3. *Kubernetes NetworkPolicy* — default-deny ingress in `sentinel-backend`, plus an allow rule scoped to the app port (5678) from the two VPC CIDRs only. Enforcement is real: the VPC CNI addon is deployed with `enableNetworkPolicy = "true"`.
- **Pod hardening:** non-root, no privilege escalation, dropped capabilities, read-only root FS (backend), resource limits, readiness probes. The gateway uses `nginx-unprivileged` listening on 8080.
- **State security:** S3 remote state with encryption and versioning; native S3 locking (`use_lockfile`) avoids needing extra DynamoDB permissions.

### Constraints found in the challenge account (documented, not bypassed)

- `iam:ListAttachedUserPolicies` / `ListUserPolicies` on my own user return `NoSuchEntity` → IAM introspection is intentionally restricted. Permissions were discovered empirically and the design stayed strictly within the `eks-`/`sentinel-` prefix guardrail.
- The account has no default VPC (clean slate) — everything is created from code.

## CI/CD pipeline structure

- Two sequential jobs (`terraform` → `deploy-apps`) in a single workflow, triggered on push; PRs get validation + plan without apply.
- A `concurrency` group serializes runs so two applies can never race on the same state.
- Static credentials are stored **only** as GitHub encrypted secrets; nothing sensitive lives in the repo.
- Lint/validate gates run *before* any apply: `terraform fmt`, `validate`, `tflint` (AWS ruleset), `kubeconform -strict`, and server-side dry-runs against the real API servers.

*Note on tooling:* the challenge mentions `kubeval`, which is archived/unmaintained; `kubeconform` is its actively maintained successor and performs the same schema validation.

## Trade-offs due to the 3-day limit

| Trade-off | POC choice | Production choice |
|---|---|---|
| Cluster API endpoint | Public+private (GitHub-hosted runners must reach it) | Private-only + self-hosted runner/CodeBuild in-VPC or VPN |
| AWS auth in CI | Static keys as GitHub secrets | **GitHub OIDC federation** with a `sentinel-github-actions` role (short-lived creds, repo/branch-scoped trust policy) |
| Load balancers | Classic ELB via the in-tree controller (zero extra IAM/Helm setup) | AWS Load Balancer Controller with NLB (IP targets) / ALB + ingress |
| NAT | 1 per VPC | 1 per AZ |
| Backend discovery | ELB DNS injected by CI | Service mesh / VPC Lattice / ExternalDNS with private Route 53 zone |
| TLS | Plain HTTP inside private links | TLS at the edge (ACM) + mTLS service-to-service |

## Cost optimization notes

- `t3.medium` nodes (smallest size that runs EKS system pods comfortably), 2 per cluster.
- Single NAT GW per VPC (~$0.05/h each saved vs per-AZ).
- Classic ELBs instead of NLB/ALB pairs — cheapest LB option and sufficient for HTTP POC traffic.
- VPC Peering: no hourly charge (unlike TGW); intra-region data transfer between AZs applies either way.
- Everything destroys cleanly with `terraform destroy` (run via a manual pipeline dispatch or locally *only for teardown* after the review).

## What I would do next

1. **GitHub OIDC federation** (`sentinel-oidc-provider` + `sentinel-github-actions` role) to eliminate long-lived keys — first thing, and the trust policy pinned to `repo:<org>/<repo>:ref:refs/heads/main`.
2. **AWS Load Balancer Controller** with IRSA for NLB/ALB, target-type IP, and TLS termination with ACM certificates.
3. **mTLS + service mesh** (Istio ambient / App Mesh successor patterns) for identity-based service auth instead of CIDR-based.
4. **Observability:** Prometheus + Grafana or CloudWatch Container Insights, ELB access logs to S3, VPC Flow Logs.
5. **GitOps:** Argo CD per cluster, with this repo as the source of truth and the pipeline reduced to CI-only.
6. **Secrets:** External Secrets Operator + AWS Secrets Manager (or Vault).
7. **Policy as code:** OPA/Conftest gates on `terraform plan` output and Kyverno in-cluster.
