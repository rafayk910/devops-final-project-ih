# Security & Compliance — Expensy

This document describes how credentials, secrets, roles, network access, and data
protection are handled in the Expensy deployment, per the project's Security &
Compliance requirements. It also records known gaps and their remediation paths, so
the current security posture is transparent rather than implied.

## 1. Identity & Access Management (IAM)

The deployment uses **scoped IAM roles throughout and never uses root credentials**
for automation.

- **CI/CD → AWS: OIDC federation, no stored keys.** GitHub Actions authenticates to
  AWS by assuming an IAM role via short-lived OpenID Connect (OIDC) tokens. No
  long-lived AWS access keys are stored in GitHub Secrets. The role's trust policy is
  scoped to this specific repository (by GitHub user ID and repo name), so no other
  repository can assume it.
  - Role: `expensy-github-actions`
  - Permissions: `AmazonEC2ContainerRegistryPowerUser` (ECR push/pull only)

- **EKS nodes: managed node-group IAM role.** Worker nodes run under a dedicated IAM
  role with only the policies required to join the cluster and pull images
  (`AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`,
  `AmazonEC2ContainerRegistryReadOnly`). Nodes can pull from ECR without any registry
  credentials embedded in the cluster.

- **CloudWatch agent: EKS Pod Identity.** The Container Insights CloudWatch agent
  assumes an IAM role (`expensy-cloudwatch-agent`, policy
  `CloudWatchAgentServerPolicy`) through EKS Pod Identity — the modern replacement for
  IRSA — rather than node-wide credentials. This scopes log/metric-write permissions
  to just the agent's service account.

- **Cluster access.** Administrative access to the cluster is granted to the
  provisioning identity via EKS access entries (`AmazonEKSClusterAdminPolicy`), not
  shared credentials.

## 2. Secrets Management

- **No secrets in version control.** Application secrets (`DATABASE_URI`,
  `REDIS_PASSWORD`, Mongo credentials) live only in a git-ignored `.env` locally and,
  at runtime, in Kubernetes Secrets. A committed `.env.example` documents the required
  variables without values. A `.env` that had been committed upstream in the base repo
  was removed from tracking (`git rm --cached`) and added to `.gitignore`.

- **Runtime injection.** Secrets are injected into containers as environment variables
  from Kubernetes Secrets — never baked into images. `.dockerignore` excludes `.env`
  files from the Docker build context so they cannot end up in an image layer.

- **CI/CD secret handling.** Because CI authenticates via OIDC, there are no AWS
  secrets to store in the pipeline. Registry access is granted through the assumed
  role at runtime.

## 3. Encryption

- **Kubernetes Secrets at rest:** encrypted with a dedicated AWS KMS key
  (key rotation enabled) via EKS envelope encryption.
- **Terraform state at rest:** the S3 state bucket enforces AES-256 server-side
  encryption, blocks all public access, and has versioning enabled for recovery.
- **In transit (current):** traffic between the browser and the load balancer is
  plain HTTP today. See Known Gaps (§6).

## 4. Network Security

- **Private worker nodes.** EKS nodes run in private subnets with no public IP
  addresses. Outbound internet access is via a NAT gateway; there is no inbound path
  to the nodes directly.
- **Single public entry point.** Only the nginx gateway is exposed publicly (via a
  `LoadBalancer` Service / AWS ELB). All application services (frontend, backend,
  mongo, redis) are `ClusterIP` — reachable only inside the cluster.
- **Instance metadata hardening.** Worker node launch templates enforce IMDSv2
  (`http_tokens = required`), mitigating the SSRF-to-credential-theft attack class.
- **Security groups** are provisioned by the EKS module and restricted to the traffic
  the cluster requires.

## 5. Logging, Monitoring & Retention

- **Control-plane logs:** EKS API, audit, authenticator, controller-manager, and
  scheduler logs are shipped to CloudWatch Logs (`/aws/eks/expensy/cluster`).
- **Application/pod logs:** collected by the `amazon-cloudwatch-observability`
  Container Insights add-on (Fluent Bit) and shipped to CloudWatch
  (`/aws/containerinsights/expensy/application`), enriched with Kubernetes metadata
  (pod, namespace, node, image).
- **Metrics:** Prometheus scrapes cluster and application metrics; Grafana visualizes
  them; the kube-prometheus-stack ships 30+ alert rule groups (pod health, node
  pressure, resource saturation) routed via Alertmanager.
- **Retention policy:** log groups are currently set to *never expire*. For production,
  a finite retention policy (e.g. 30–90 days) should be applied to control cost and
  meet data-retention requirements.

## 6. Known Gaps & Remediation

These are documented deliberately; the deployment is a course project, and naming
gaps is part of an honest security posture.

| Gap | Current state | Production remediation |
| --- | --- | --- |
| TLS/HTTPS | Plain HTTP on the ELB | Terminate TLS at an ALB/Ingress with an ACM certificate, or cert-manager + Let's Encrypt on a real domain |
| Demo credentials | Placeholder DB/Redis credentials in committed K8s Secret manifests | Move secrets to AWS Secrets Manager via the External Secrets Operator, or SealedSecrets; remove plaintext from git |
| Log retention | Never-expire | Set 30–90 day retention on CloudWatch log groups |
| Data services | Mongo/Redis run as in-cluster pods with ephemeral storage | Use managed data services (DocumentDB/ElastiCache) or add the EBS CSI driver for persistent, encrypted volumes with backups |

## 7. Data Protection & Compliance Notes

Expensy stores expense records (name, amount, category) in MongoDB. No special-category
personal data (health, financial account numbers, etc.) is collected in the current
scope. All infrastructure is provisioned in the **eu-central-1 (Frankfurt)** region,
keeping data within the EU — relevant if GDPR applies. Secrets and Kubernetes state are
encrypted at rest (KMS); Terraform state is encrypted in S3. For a production system
handling real user data, a formal retention policy, TLS in transit, and an external
secrets manager (above) would be prerequisites.
