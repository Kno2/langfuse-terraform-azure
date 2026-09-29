locals {
  langfuse_values = <<EOT
langfuse:
  image:
    tag: ${jsonencode(var.app_version)}
  salt:
    secretKeyRef:
      name: langfuse
      key: salt
  nextauth:
    url: "https://${var.domain}"
    secret:
      secretKeyRef:
        name: langfuse
        key: nextauth-secret
  features:
    signUpDisabled: ${var.signup_disabled}
postgresql:
  deploy: false
  host: ${azurerm_private_endpoint.postgres.private_service_connection[0].private_ip_address}:5432
  auth:
    username: ${azurerm_postgresql_flexible_server.this.administrator_login}
    database: langfuse
    existingSecret: langfuse
    secretKeys:
      userPasswordKey: postgres-password
redis:
  deploy: false
  host: ${azurerm_managed_redis.this.hostname}
  port: ${azurerm_managed_redis.this.default_database[0].port}
  tls:
    enabled: true
  # Azure Managed Redis uses the OSSCluster clustering policy (see redis.tf),
  # so Langfuse must use its cluster-aware client with hash-tagged queue keys;
  # a standalone connection fails with CROSSSLOT errors on every ingestion.
  cluster:
    enabled: true
    nodes:
      - "${azurerm_managed_redis.this.hostname}:${azurerm_managed_redis.this.default_database[0].port}"
  auth:
    existingSecret: langfuse
    existingSecretPasswordKey: redis-password
s3:
  deploy: false
  storageProvider: "azure"
  endpoint: https://${azurerm_storage_account.this.name}.blob.core.windows.net
  bucket: ${azurerm_storage_container.this.name}
  region: ${azurerm_storage_account.this.location}
  accessKeyId:
    value: ${azurerm_storage_account.this.name}
  secretAccessKey:
    secretKeyRef:
      name: ${kubernetes_secret_v1.langfuse.metadata[0].name}
      key: storage-access-key
  forcePathStyle: false
  eventUpload:
    prefix: "events/"
  batchExport:
    prefix: "exports/"
  mediaUpload:
    prefix: "media/"
EOT

  # In-cluster ClickHouse: the Langfuse Helm chart v2 renders ClickHouseCluster
  # and KeeperCluster resources reconciled by the ClickHouse operator (see
  # clickhouse.tf). The operator's CRD default logger level is `trace`, which
  # logs every Keeper heartbeat, so pin both to `information`.
  clickhouse_internal_values = !local.deploy_clickhouse ? "" : <<EOT
clickhouse:
  deploy: true
  auth:
    existingSecret: langfuse
    existingSecretKey: clickhouse-password
  cluster:
    replicas: ${var.clickhouse_replicas}
    storage:
      size: ${var.clickhouse_storage_size}
      className: ${var.clickhouse_storage_class}
    resources:
      requests:
        cpu: ${jsonencode(var.clickhouse_resources.cpu)}
        memory: ${jsonencode(var.clickhouse_resources.memory)}
      limits:
        cpu: ${jsonencode(var.clickhouse_resources.cpu)}
        memory: ${jsonencode(var.clickhouse_resources.memory)}
    logger:
      level: information
  keeper:
    replicas: ${var.clickhouse_keeper_replicas}
    storage:
      size: ${var.clickhouse_keeper_storage_size}
      className: ${var.clickhouse_storage_class}
    logger:
      level: information
EOT

  # External ClickHouse: skip the in-cluster deployment and point Langfuse at
  # the provided instance.
  clickhouse_external_values = local.deploy_clickhouse ? "" : <<EOT
clickhouse:
  deploy: false
  host: ${jsonencode(var.external_clickhouse.host)}
  httpPort: ${var.external_clickhouse.http_port}
  nativePort: ${var.external_clickhouse.native_port}
  database: ${jsonencode(var.external_clickhouse.database)}
  cluster:
    enabled: ${var.external_clickhouse.cluster_enabled}
  auth:
    username: ${jsonencode(var.external_clickhouse.username)}
    existingSecret: langfuse
    existingSecretKey: clickhouse-password
  migration:
    ssl: ${var.external_clickhouse.migration_ssl}
EOT

  clickhouse_values = local.deploy_clickhouse ? local.clickhouse_internal_values : local.clickhouse_external_values

  replica_values = var.langfuse_replicas == null ? "" : <<EOT
langfuse:
  replicas: ${var.langfuse_replicas}
EOT

  encryption_values = var.use_encryption_key == false ? "" : <<EOT
langfuse:
  encryptionKey:
    secretKeyRef:
      name: ${kubernetes_secret_v1.langfuse.metadata[0].name}
      key: encryption-key
EOT
  # Entra ID (Azure AD) SSO. The chart's nextauthEnv helper walks
  # langfuse.auth.providers.<name>.<option> and emits AUTH_<NAME>_<OPTION>, so
  # azureAd.clientId becomes AUTH_AZURE_AD_CLIENT_ID. Map-valued options go through
  # getValueOrSecret, which is how clientSecret stays a secretKeyRef instead of
  # being rendered in plaintext into the Helm release values.
  #
  # disableUsernamePassword is emitted whenever the auth key exists, so this block
  # is all-or-nothing on azure_ad_client_id: with SSO unconfigured we must not
  # render the block at all, or we would emit AUTH_DISABLE_USERNAME_PASSWORD with
  # no provider to fall back to.
  auth_values = var.azure_ad_client_id == null ? "" : <<EOT
langfuse:
  auth:
    disableUsernamePassword: ${var.disable_username_password}
    providers:
      azureAd:
        clientId: "${var.azure_ad_client_id}"
        tenantId: "${var.azure_ad_tenant_id}"
        allowAccountLinking: ${var.azure_ad_allow_account_linking}
        clientSecret:
          secretKeyRef:
            name: ${kubernetes_secret_v1.langfuse.metadata[0].name}
            key: azure-ad-client-secret
EOT
  # Environment variables the module itself must always inject. REDIS_TLS_SERVERNAME
  # provides the SNI needed to TLS-handshake with the shard endpoints announced by
  # the Azure Managed Redis OSS cluster (see redis.tf); without it the worker fails
  # with "tlsv1 alert decode error" and crash-loops, blocking all ingestion.
  #
  # These MUST share a single rendered additionalEnv list with var.additional_env:
  # Helm replaces (does not merge) lists, so two separate additionalEnv blocks would
  # collide and the last one wins, silently dropping the other's entries.
  required_env = [
    {
      name      = "REDIS_TLS_SERVERNAME"
      value     = azurerm_managed_redis.this.hostname
      valueFrom = null
    },
  ]
  all_additional_env = concat(local.required_env, var.additional_env)

  additional_env_values = length(local.all_additional_env) == 0 ? "" : <<EOT
langfuse:
  additionalEnv:
%{for env in local.all_additional_env}
  - name: ${env.name}
%{if env.value != null}
    value: "${env.value}"
%{endif}
%{if env.valueFrom != null}
    valueFrom:
%{if env.valueFrom.secretKeyRef != null}
      secretKeyRef:
        name: ${env.valueFrom.secretKeyRef.name}
        key: ${env.valueFrom.secretKeyRef.key}
%{endif}
%{if env.valueFrom.configMapKeyRef != null}
      configMapKeyRef:
        name: ${env.valueFrom.configMapKeyRef.name}
        key: ${env.valueFrom.configMapKeyRef.key}
%{endif}
%{endif}
%{endfor}
EOT
}

resource "kubernetes_namespace_v1" "langfuse" {
  metadata {
    name = "langfuse"
  }
}

resource "random_bytes" "salt" {
  # Should be at least 256 bits (32 bytes): https://langfuse.com/self-hosting/configuration#core-infrastructure-settings ~> SALT
  length = 32
}

resource "random_bytes" "nextauth_secret" {
  # Should be at least 256 bits (32 bytes): https://langfuse.com/self-hosting/configuration#core-infrastructure-settings ~> NEXTAUTH_SECRET
  length = 32
}

resource "random_bytes" "encryption_key" {
  count = var.use_encryption_key ? 1 : 0
  # Must be exactly 256 bits (32 bytes): https://langfuse.com/self-hosting/configuration#core-infrastructure-settings ~> ENCRYPTION_KEY
  length = 32
}

resource "kubernetes_secret_v1" "langfuse" {
  metadata {
    name      = "langfuse"
    namespace = "langfuse"
  }

  data = {
    "redis-password"      = azurerm_managed_redis.this.default_database[0].primary_access_key
    "postgres-password"   = azurerm_postgresql_flexible_server.this.administrator_password
    "storage-access-key"  = azurerm_storage_account.this.primary_access_key
    "salt"                = random_bytes.salt.base64
    "nextauth-secret"     = random_bytes.nextauth_secret.base64
    "clickhouse-password" = local.deploy_clickhouse ? random_password.clickhouse_password.result : var.external_clickhouse_password
    "encryption-key"      = var.use_encryption_key ? random_bytes.encryption_key[0].hex : ""
    "smtp-connection"     = var.smtp_connection_value
    # Always present so the secretKeyRef in auth_values resolves; empty when SSO is unconfigured.
    "azure-ad-client-secret" = var.azure_ad_client_secret_value == null ? "" : var.azure_ad_client_secret_value
  }
}

resource "helm_release" "langfuse" {
  name             = "langfuse"
  repository       = "https://langfuse.github.io/langfuse-k8s"
  version          = var.langfuse_helm_chart_version
  chart            = "langfuse"
  namespace        = "langfuse"
  create_namespace = true

  values = [
    local.langfuse_values,
    local.clickhouse_values,
    local.ingress_values,
    local.encryption_values,
    local.auth_values,
    local.replica_values,
    local.additional_env_values
  ]

  depends_on = [
    kubernetes_secret_v1.langfuse,
    helm_release.clickhouse_operator,
  ]

  lifecycle {
    precondition {
      condition     = var.external_clickhouse == null || var.external_clickhouse_password != ""
      error_message = "external_clickhouse_password must be set when external_clickhouse is configured."
    }
  }
}
