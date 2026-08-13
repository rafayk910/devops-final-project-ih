# Expensy — End-to-End DevOps Deployment

Expensy is a lightweight expense-tracker application (Next.js frontend, Node/Express
backend, MongoDB, Redis) deployed through a full DevOps lifecycle: containerized,
built and pushed by CI/CD, provisioned on AWS EKS with Terraform, and observed with
Prometheus/Grafana and CloudWatch.

This README covers local development, container usage, and cloud deployment. See
[`SECURITY.md`](./SECURITY.md) for the security and compliance posture, and
[`monitoring/README.md`](./monitoring/README.md) for the monitoring stack.

## Architecture

```
Browser
   │
   ▼
AWS Load Balancer (ELB)
   │
   ▼
nginx gateway (single entry point)
   ├── /api/*  ──▶ backend  (Node/Express, :8706, 2 replicas)
   └── /*      ──▶ frontend (Next.js, :3000, 2 replicas)
                      │
              ┌───────┴────────┐
              ▼                ▼
           MongoDB           Redis
        (:27017)           (:6379)
```

- **Frontend** exposes `NEXT_PUBLIC_API_URL=/api` (a relative path), so a single image
  works in every environment — no per-environment rebuild.
- **Gateway** (nginx) merges frontend and backend behind one origin, so requests are
  same-origin (no CORS) and only one port is public.
- All data services and app services are internal (`ClusterIP`); only the gateway is
  exposed via `LoadBalancer`.

## Repository layout

```
.
├── expensy_frontend/      # Next.js app + Dockerfile
├── expensy_backend/       # Node/Express API (TypeScript) + Dockerfile
├── nginx/                 # gateway reverse-proxy config
├── docker-compose.yaml    # full local stack (all 4 services + gateway)
├── k8s/                   # Kubernetes manifests (namespace, config, deployments, services, HPA)
├── infrastructure/
│   ├── bootstrap/         # S3 + DynamoDB remote-state backend
│   └── main/              # VPC + EKS cluster (Terraform)
├── monitoring/            # Grafana dashboard JSON exports + install notes
├── .github/workflows/     # CI/CD pipeline (ci-cd.yaml)
├── SECURITY.md
└── README.md
```

## 1. Local development

### Prerequisites
- Docker, Node.js 24, npm

### Option A — full stack via docker-compose (recommended)

```bash
docker compose up --build
```

Open **http://localhost:8080** (the gateway). This runs frontend, backend, MongoDB,
Redis, and the nginx gateway together with correct service-name networking and
authenticated Redis.

### Option B — run services directly (for active development)

Start the datastores:

```bash
docker run --name mongo -d -p 27017:27017 \
  -e MONGO_INITDB_ROOT_USERNAME=root -e MONGO_INITDB_ROOT_PASSWORD=example mongo:latest

docker run --name redis -d -p 6379:6379 redis:latest
```

Backend — create `expensy_backend/.env` (see `expensy_backend/.env.example`):

```
PORT=8706
DATABASE_URI=mongodb://root:example@127.0.0.1:27017/expensy?authSource=admin
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
```

```bash
cd expensy_backend && npm install && npm start
```

Frontend — create `expensy_frontend/.env.local`:

```
NEXT_PUBLIC_API_URL=http://localhost:8706
```

```bash
cd expensy_frontend && npm install && npm run dev
```

> Note: when running the backend on the host (not in Docker), use `127.0.0.1` for the
> datastores. Inside docker-compose/Kubernetes the hostnames are the service names
> (`mongo`, `redis`).

## 2. Containers

Each service has a multi-stage Dockerfile.

- **Backend** (`expensy_backend/Dockerfile`): builds TypeScript in a builder stage,
  runs only the compiled output as a non-root user. Config is injected at runtime
  via environment variables.
- **Frontend** (`expensy_frontend/Dockerfile`): Next.js build. Because `NEXT_PUBLIC_*`
  variables are inlined at **build time**, `NEXT_PUBLIC_API_URL` is passed as a
  `--build-arg`:

```bash
docker build --build-arg NEXT_PUBLIC_API_URL=/api -t expensy-frontend .
```

## 3. CI/CD

`.github/workflows/ci-cd.yaml` runs on push to `main`:

1. **build-test** — installs and builds both frontend and backend (catches compile errors).
2. **docker-push** (main only) — authenticates to AWS via **OIDC** (no stored keys),
   logs in to ECR, builds both images tagged with the commit SHA, and pushes them.

Images are pushed to Amazon ECR (`expensy-backend`, `expensy-frontend`). See
`SECURITY.md` for the OIDC trust configuration.

## 4. Deploy to AWS (EKS)

### Prerequisites
- AWS CLI configured, Terraform ≥ 1.5, `kubectl`, `helm`

### Step 1 — remote state backend (once)

```bash
cd infrastructure/bootstrap
terraform init && terraform apply     # creates the S3 state bucket + DynamoDB lock table
```

### Step 2 — provision the cluster

```bash
cd ../main
terraform init
terraform apply                        # VPC + EKS cluster + node group (~15 min)
```

### Step 3 — connect kubectl & deploy the app

```bash
aws eks update-kubeconfig --region eu-central-1 --name expensy
kubectl get nodes                      # confirm 2 nodes Ready
kubectl apply -f k8s/                   # namespace, config, datastores, apps, gateway, HPA
kubectl get pods -n expensy            # wait until all Running
```

### Step 4 — get the public URL

```bash
kubectl get svc -n expensy gateway     # EXTERNAL-IP is the app's public URL
```

Open the ELB hostname in a browser — Expensy is live.

### Monitoring

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace
```

See [`monitoring/README.md`](./monitoring/README.md) for accessing Grafana and the
dashboard exports. Logs flow to CloudWatch via the `amazon-cloudwatch-observability`
EKS add-on (control-plane logs enabled in Terraform).

### Teardown

```bash
kubectl delete -f k8s/                  # remove app first so the ELB is released
cd infrastructure/main
terraform destroy                        # tears down the cluster and VPC
```

> Teardown order matters: delete the Kubernetes `LoadBalancer` Service before
> `terraform destroy`, or the leftover ELB can block VPC deletion.

## Environment variables

| Variable | Service | Purpose |
| --- | --- | --- |
| `DATABASE_URI` | backend | MongoDB connection string (with `authSource=admin`) |
| `REDIS_HOST` / `REDIS_PORT` / `REDIS_PASSWORD` | backend | Redis connection |
| `PORT` | backend | API port (8706) |
| `NEXT_PUBLIC_API_URL` | frontend | Backend URL — `/api` in-cluster (build-time) |

Secrets are never committed. In-cluster they are provided via Kubernetes Secrets;
locally via git-ignored `.env` / `.env.local` files (templates: `.env.example`).

## Tech stack

Next.js · Node/Express (TypeScript) · MongoDB · Redis · Docker · nginx ·
GitHub Actions (OIDC) · Amazon ECR · Terraform · Amazon EKS · Kubernetes ·
Prometheus · Grafana · Amazon CloudWatch
