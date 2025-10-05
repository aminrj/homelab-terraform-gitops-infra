# The Hidden Cost of Kubernetes Health Checks: Debugging Readiness Probe Failures

*A deep dive into why your pods are stuck at 0/1 READY, even though the application is running perfectly. Real-world debugging of commafeed's mysterious 404 readiness probe failures.*

## The Symptom

Everything looked good. My commafeed deployment succeeded. The database was healthy. The logs showed the application started successfully. But Kubernetes disagreed:

```bash
$ kubectl get pods -n commafeed-prod
NAME                        READY   STATUS    RESTARTS      AGE
commafeed-bdfb9b94f-n2vm4   0/1     Running   3 (39s ago)   3m20s
```

`0/1 READY`. The pod has been running for over 3 minutes, restarting periodically, never becoming ready.

This is one of the most frustrating problems in Kubernetes: the application works, but health probes fail. Let me show you how to debug this systematically.

## Understanding Health Probes

Kubernetes has three types of health probes:

### 1. Liveness Probe
**Purpose:** Is the application alive?
**Action on failure:** Restart the container
**Use when:** Application can get stuck (deadlocks, infinite loops)

```yaml
livenessProbe:
  httpGet:
    path: /q/health/live
    port: 8082
  initialDelaySeconds: 30  # Wait 30s before first check
  periodSeconds: 10        # Check every 10s
  failureThreshold: 3      # Restart after 3 consecutive failures
```

### 2. Readiness Probe
**Purpose:** Is the application ready to serve traffic?
**Action on failure:** Remove from service endpoints (no traffic sent)
**Use when:** Application needs startup time (DB connections, cache warming)

```yaml
readinessProbe:
  httpGet:
    path: /q/health/ready
    port: 8082
  initialDelaySeconds: 5   # Check quickly
  periodSeconds: 5         # Check frequently
  failureThreshold: 3      # Mark unready after 3 failures
```

### 3. Startup Probe
**Purpose:** Has the application finished starting?
**Action on failure:** Restart (liveness/readiness disabled until this succeeds)
**Use when:** Application has long startup time

```yaml
startupProbe:
  httpGet:
    path: /health/startup
    port: 8082
  initialDelaySeconds: 0
  periodSeconds: 10
  failureThreshold: 30     # Allow 5 minutes (30 * 10s)
```

**Probe evaluation order:**
1. Startup probe (if defined) must pass first
2. Then liveness probe starts checking
3. Then readiness probe starts checking

## The Debugging Process

Back to my commafeed problem. Here's how I debugged it step by step.

### Step 1: Check Pod Events

```bash
$ kubectl describe pod commafeed-bdfb9b94f-n2vm4 -n commafeed-prod
Name:             commafeed-bdfb9b94f-n2vm4
Namespace:        commafeed-prod
Status:           Running
# ...

Conditions:
  Type              Status
  Initialized       True
  Ready             False  # <-- Not ready
  ContainersReady   False  # <-- Container not ready
  PodScheduled      True

# Scroll down to Events
Events:
  Type     Reason     Age                    From               Message
  ----     ------     ----                   ----               -------
  Normal   Scheduled  5m                     default-scheduler  Successfully assigned commafeed-prod/commafeed-bdfb9b94f-n2vm4 to microk8snode1
  Normal   Pulled     5m                     kubelet            Container image "athou/commafeed:latest-postgresql" already present on machine
  Normal   Created    5m                     kubelet            Created container commafeed
  Normal   Started    5m                     kubelet            Started container commafeed
  Warning  Unhealthy  2m (x15 over 5m)       kubelet            Readiness probe failed: HTTP probe failed with statuscode: 404
```

**Key finding:** `Readiness probe failed: HTTP probe failed with statuscode: 404`

The probe is hitting the endpoint, getting a response, but it's a 404. The endpoint doesn't exist.

### Step 2: Check Probe Configuration

```bash
$ kubectl get deployment commafeed -n commafeed-prod -o yaml | grep -A 10 readinessProbe
readinessProbe:
  httpGet:
    path: /q/health/ready
    port: 8082
  initialDelaySeconds: 5
  periodSeconds: 5
  failureThreshold: 3
```

The probe is checking `/q/health/ready` on port 8082. Let's verify the application logs.

### Step 3: Check Application Logs

```bash
$ kubectl logs -n commafeed-prod deployment/commafeed --tail=50
2025-10-04 22:33:55,528 INFO  [io.quarkus] (main) commafeed-server 5.11.0 native (powered by Quarkus 3.25.0) started in 0.739s. Listening on: http://0.0.0.0:8082
2025-10-04 22:33:55,528 INFO  [io.quarkus] (main) Profile prod activated.
2025-10-04 22:33:55,528 INFO  [io.quarkus] (main) Installed features: [agroal, cdi, hibernate-orm, hibernate-validator, jdbc-postgresql, liquibase, mailer, narayana-jta, qute, rest, rest-jackson, security, smallrye-context-propagation, smallrye-openapi, swagger-ui, vertx, websockets, websockets-client]
```

The application started successfully on port 8082. No errors. But is `/q/health/ready` actually available?

### Step 4: Test the Endpoint Directly

```bash
# Port-forward to access the pod directly
$ kubectl port-forward -n commafeed-prod deployment/commafeed 8082:8082 &

# Test the readiness endpoint
$ curl -I http://localhost:8082/q/health/ready
HTTP/1.1 404 Not Found
content-length: 0

# Aha! The endpoint returns 404

# What about the liveness endpoint?
$ curl -I http://localhost:8082/q/health/live
HTTP/1.1 404 Not Found
content-length: 0

# Also 404!

# What about the root path?
$ curl -I http://localhost:8082/
HTTP/1.1 200 OK
Content-Type: text/html;charset=UTF-8
Content-Length: 2847

# Root path works!
```

**Root cause identified:** The Quarkus health endpoints `/q/health/*` are not enabled in this commafeed image, even though the deployment configuration expects them.

### Step 5: Check Application Documentation

Quick research on the commafeed Docker image shows it's a Quarkus application, but the health endpoints might not be exposed by default, or they might be at a different path.

**Options:**
1. Find the correct health endpoint path
2. Use a basic HTTP check on `/` instead
3. Enable health endpoints via environment variables

I chose option 2 - simplest and most reliable.

## The Fix

Update the readiness probe to use a path that actually exists:

```yaml
# Before (WRONG - endpoint doesn't exist)
readinessProbe:
  httpGet:
    path: /q/health/ready
    port: 8082
  initialDelaySeconds: 5
  periodSeconds: 5

# After (RIGHT - root path exists and returns 200)
readinessProbe:
  httpGet:
    path: /
    port: 8082
  initialDelaySeconds: 10  # Give it a bit more time
  periodSeconds: 10        # Check less frequently
```

Apply the fix:

```bash
$ kubectl apply -k apps/commafeed/overlays/prod/

# Wait for new pod
$ kubectl get pods -n commafeed-prod -w
NAME                         READY   STATUS    RESTARTS   AGE
commafeed-794bb5dcb7-rbs8z   0/1     Running   0          10s
commafeed-794bb5dcb7-rbs8z   1/1     Running   0          16s

# Success! Pod is ready
```

## Common Health Probe Pitfalls

### Pitfall 1: Wrong Path

**Problem:**
```yaml
readinessProbe:
  httpGet:
    path: /health  # Path doesn't exist
```

**Symptoms:**
- Pod stuck at 0/1 READY
- `kubectl describe pod` shows "HTTP probe failed with statuscode: 404"

**Solution:**
```bash
# Find the correct health endpoint
kubectl exec -it deployment/myapp -- curl localhost:8080/health
kubectl exec -it deployment/myapp -- curl localhost:8080/healthz
kubectl exec -it deployment/myapp -- curl localhost:8080/

# Or check application documentation
```

### Pitfall 2: Wrong Port

**Problem:**
```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8080  # Application listens on 3000
```

**Symptoms:**
- `kubectl describe pod` shows "connection refused"
- Logs show application running on different port

**Solution:**
```bash
# Check what port the application actually uses
kubectl logs deployment/myapp | grep -i "listening\|port\|started"

# Match the probe port to the application port
ports:
  - containerPort: 3000  # Application port
readinessProbe:
  httpGet:
    port: 3000  # Must match
```

### Pitfall 3: Too Aggressive Timing

**Problem:**
```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 1   # Too short!
  periodSeconds: 1         # Too frequent!
  failureThreshold: 1      # Too strict!
```

**Symptoms:**
- Pod fails readiness before application finishes starting
- Pod constantly restarting

**Solution:**
```yaml
# Give the application time to start
readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30  # Wait for startup
  periodSeconds: 10        # Check every 10s
  failureThreshold: 3      # Allow temporary failures
```

**Timing guidelines:**
- **initialDelaySeconds:** How long does your app take to start? Add buffer.
- **periodSeconds:** How often to check? 5-10s is usually fine.
- **failureThreshold:** Allow transient failures. 3-5 is good.

### Pitfall 4: Probe Fails Under Load

**Problem:**
Application's health endpoint is expensive and times out under load.

**Symptoms:**
- Pods cycle in/out of ready state
- Readiness flapping during traffic spikes
- `kubectl describe pod` shows "HTTP probe failed: timeout"

**Solution:**
```yaml
# Use a lightweight health endpoint
readinessProbe:
  httpGet:
    path: /health/lightweight  # Doesn't query database
    port: 8080
  timeoutSeconds: 3  # Increase timeout
  periodSeconds: 10  # Check less frequently
```

**Health endpoint best practices:**
- Don't query databases (use connection pool state instead)
- Don't call external services
- Return quickly (< 100ms)
- Cache results if expensive checks needed

### Pitfall 5: Readiness vs. Liveness Confusion

**Problem:**
Using the same endpoint for both with same thresholds.

**Symptoms:**
- Application restarts when it should just stop receiving traffic
- Cascading failures during partial outages

**Wrong:**
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  failureThreshold: 2  # Restart after 2 failures

readinessProbe:
  httpGet:
    path: /health      # Same endpoint
    port: 8080
  failureThreshold: 2  # Same threshold
```

**Right:**
```yaml
# Liveness: Is the process alive? (conservative)
livenessProbe:
  httpGet:
    path: /health/live  # Basic process check
    port: 8080
  failureThreshold: 5   # More tolerant - restarts are expensive

# Readiness: Can it serve traffic? (strict)
readinessProbe:
  httpGet:
    path: /health/ready  # Includes dependency checks
    port: 8080
  failureThreshold: 2    # Less tolerant - just remove from LB
```

## Advanced Debugging Techniques

### Technique 1: Exec Into Pod and Test

```bash
# Access the pod
kubectl exec -it deployment/commafeed -n commafeed-prod -- /bin/sh

# Test endpoints manually (if curl available)
curl -v http://localhost:8082/q/health/ready
curl -v http://localhost:8082/

# If curl not available, use wget
wget -O- http://localhost:8082/q/health/ready

# Or use nc (netcat)
echo -e "GET /q/health/ready HTTP/1.1\nHost: localhost\n\n" | nc localhost 8082
```

### Technique 2: Disable Probe Temporarily

To test if the probe is the problem:

```yaml
# Comment out readiness probe temporarily
# readinessProbe:
#   httpGet:
#     path: /q/health/ready
#     port: 8082
```

Apply and check:
```bash
kubectl apply -k apps/commafeed/overlays/prod/

kubectl get pods -n commafeed-prod
# If pod becomes ready, probe configuration is the issue
```

**Warning:** Don't leave probes disabled in production!

### Technique 3: Increase Verbosity in Events

```bash
# Watch events in real-time
kubectl get events -n commafeed-prod --watch

# Filter for specific pod
kubectl get events -n commafeed-prod --field-selector involvedObject.name=commafeed-794bb5dcb7-rbs8z

# See HTTP response codes and details
kubectl describe pod commafeed-794bb5dcb7-rbs8z -n commafeed-prod | grep -A 5 "Unhealthy"
```

### Technique 4: Use tcpdump to Inspect Traffic

```bash
# Capture HTTP traffic to the pod
kubectl exec -it deployment/commafeed -n commafeed-prod -- tcpdump -i any -A port 8082

# In another terminal, trigger the probe
kubectl delete pod <pod-name> -n commafeed-prod
# Watch the readiness probe HTTP requests in tcpdump

# Or install debug container
kubectl debug -it deployment/commafeed --image=nicolaka/netshoot
# Then use tcpdump, curl, etc.
```

## Probe Strategy by Application Type

### Web Applications (REST APIs, Websites)

```yaml
livenessProbe:
  httpGet:
    path: /health/live
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /health/ready
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5
  failureThreshold: 2
```

### Databases (PostgreSQL via CNPG)

CNPG handles this automatically, but if you're running raw PostgreSQL:

```yaml
livenessProbe:
  exec:
    command:
    - /bin/sh
    - -c
    - pg_isready -U postgres
  initialDelaySeconds: 60
  periodSeconds: 10

readinessProbe:
  exec:
    command:
    - /bin/sh
    - -c
    - pg_isready -U postgres && psql -U postgres -c "SELECT 1"
  initialDelaySeconds: 30
  periodSeconds: 5
```

### Background Workers/Cron Jobs

Often don't need readiness probes (no traffic to serve), but liveness is useful:

```yaml
livenessProbe:
  exec:
    command:
    - /bin/sh
    - -c
    - pgrep -f "worker.py" || exit 1
  initialDelaySeconds: 10
  periodSeconds: 30
  failureThreshold: 3

# No readiness probe - doesn't serve traffic
```

### gRPC Applications

```yaml
livenessProbe:
  grpc:
    port: 9090
  initialDelaySeconds: 10

readinessProbe:
  grpc:
    port: 9090
    service: myapp.health.HealthCheck
  initialDelaySeconds: 5
```

### TCP Services (Redis, Memcached)

```yaml
livenessProbe:
  tcpSocket:
    port: 6379
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  exec:
    command:
    - redis-cli
    - ping
  initialDelaySeconds: 10
  periodSeconds: 5
```

## When NOT to Use Probes

### Don't Use Readiness Probe When:
1. **Single replica deployments with no load balancer** - Pod will be restarted by liveness anyway
2. **Jobs/CronJobs** - They're not serving traffic
3. **Init containers** - Use container startup order instead

### Don't Use Liveness Probe When:
1. **Application has long startup time** - Use startup probe instead
2. **Restarts don't help** - If the issue persists after restart
3. **During development** - Makes debugging harder

## Monitoring Health Probe Failures

Set up alerts for probe failures:

```yaml
# Prometheus alert
- alert: PodNotReady
  expr: kube_pod_status_ready{condition="false"} == 1
  for: 5m
  annotations:
    summary: "Pod {{ $labels.pod }} not ready for 5m"

- alert: HighReadinessProbeFailures
  expr: |
    rate(prober_probe_total{probe_type="Readiness",result="failed"}[5m]) > 0.1
  annotations:
    summary: "High readiness probe failure rate"
```

## The Complete Debugging Checklist

When a pod won't become ready:

- [ ] Check `kubectl get pods` - Is it Running but not Ready?
- [ ] Check `kubectl describe pod` - What do Events say?
- [ ] Check `kubectl logs` - Is the application started?
- [ ] Verify probe path exists: `kubectl exec` + `curl`
- [ ] Verify probe port matches container port
- [ ] Check timing: Is `initialDelaySeconds` too short?
- [ ] Test endpoint returns 200 OK (not 404, 500, etc.)
- [ ] Check endpoint responds quickly (< timeoutSeconds)
- [ ] Verify no authentication required on health endpoint
- [ ] Check if endpoint works from outside pod (DNS, network policies)
- [ ] Review application startup logs for errors
- [ ] Temporarily disable probe to confirm it's the issue

## Conclusion

Health probes are critical for reliable Kubernetes deployments, but they're also a common source of frustration. My commafeed incident taught me:

1. **Applications don't always match expectations** - Just because Quarkus apps can have `/q/health/*` endpoints doesn't mean this image has them enabled
2. **Test before deploying** - Port-forward and curl the health endpoint before configuring probes
3. **Start simple** - Using `/` as a health check is fine if it returns 200
4. **Logs are your friend** - Application logs + describe pod + events = full picture
5. **Timing matters** - Give applications time to start before checking health

**Quick wins:**
- Use `path: /` if no dedicated health endpoint exists
- Set `initialDelaySeconds` to actual startup time + buffer
- Keep `periodSeconds` reasonable (5-10s)
- Use `failureThreshold: 3` to allow transient failures
- Monitor probe failures in production

Your applications will thank you with fewer mysterious restarts and faster deployments.

---

**Related Reading:**
- [GitOps Disaster Recovery](#) - When probes save you from outages
- [Kustomize Overlays in Practice](#) - Managing probe configs across environments
- [Terraform + ArgoCD GitOps Stack](#) - Deploying applications with proper health checks

**Code Repository:** [github.com/aminrj/homelab-terraform-gitops-infra](https://github.com/aminrj/homelab-terraform-gitops-infra)
