# =========================
# CONFIGURAÇÃO INICIAL
# ========================
$clientId = “digite aqui o Client ID do App Registration"
$tenantId = “digite aqui o Tenant ID do App Registration"
$clientSecret = “Digite aqui o valor do segredo do App Registration"


# Destinatários
$notificationEmails = @("italo.silva@sga.com.br")  # <--- AQUI vão os DESTINATÁRIOS
$senderEmail = "t.italo.silva@EROBR.COM"           # <--- E-mail configurado no App Registration como remetente autorizado
$expirationThresholdDays = 30
$today = Get-Date
$emailSubject = "Ero Brasil - Alerta de Expiracao de Client Secret do App Registration"

# ========================
# OBTÉM TOKEN DE ACESSO
# ========================
$tokenUri = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
$body = @{
    client_id     = $clientId
    scope         = "https://graph.microsoft.com/.default"
    client_secret = $clientSecret
    grant_type    = "client_credentials"
}
$response = Invoke-RestMethod -Method Post -Uri $tokenUri -Body $body
$token = $response.access_token
if (-not $token) {
    Write-Output "Falha ao obter token de acesso."
    exit 1
}
Write-Output "Token de acesso obtido com sucesso."

# ========================
# CONSULTA O APP REGISTRATION
# ========================
$headers = @{ Authorization = "Bearer $token" }
$appList = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/applications" -Headers $headers
$app = $appList.value | Where-Object { $_.appId -eq $clientId }

if (-not $app) {
    Write-Output "App Registration nao encontrado com appId $clientId."
    exit 1
} else {
    Write-Output "App encontrado: $($app.displayName)"
}

# ========================
# VERIFICA SEGREDOS DO CLIENTE
# ========================
$secretsUri = "https://graph.microsoft.com/v1.0/applications/$($app.id)?`$select=passwordCredentials,displayName"
$appDetail = Invoke-RestMethod -Uri $secretsUri -Headers $headers

$expiringSecrets = @()
foreach ($secret in $appDetail.passwordCredentials) {
    $endDate = [datetime]$secret.endDateTime
    $daysRemaining = ($endDate - $today).Days
    if ($daysRemaining -le $expirationThresholdDays) {
        $expiringSecrets += [PSCustomObject]@{
            DisplayName   = $appDetail.displayName
            EndDate       = $endDate
            DaysRemaining = $daysRemaining
        }
    }
}

# ========================
# MONTAGEM DO CORPO DO EMAIL COM HTML E ESCAPANDO CARACTERES ESPECIAIS
# ========================
if ($expiringSecrets.Count -gt 0) {
    $emailBody = "<html><body>"
    $emailBody += "<p>Os seguintes segredos do App Registration estao prestes a expirar:</p>"
    $emailBody += "<ul>"
    foreach ($secret in $expiringSecrets) {
        $displayName = [System.Web.HttpUtility]::HtmlEncode($secret.DisplayName)
        $expDate = $secret.EndDate.ToString('yyyy-MM-dd')
        $daysRem = $secret.DaysRemaining
        $emailBody += "<li><b>App:</b> $displayName - <b>Expira em:</b> $expDate - <b>Dias restantes:</b> $daysRem</li>"
    }
    $emailBody += "</ul>"
    $emailBody += "<p><b>Atencao:</b> Apos renovar o segredo do App Registration, atualize este runbook: <b>verificar-expiracao-secrets-app-registration</b> (<a href='https://portal.azure.com/#@EROBR.COM/resource/subscriptions/bfa0b9c1-29a4-464c-96c7-3894238f8250/resourceGroups/RG-DATA-ERO-BR/providers/Microsoft.Automation/automationAccounts/automation-send-alert-expired-secret-app-reg/runbooks/verificar-expiracao-secrets-app-registration/overview' target='_blank'>Link</a>) com o novo valor do <b>clientSecret</b> gerado.</p>"
    $emailBody += "</body></html>"
} else {
    Write-Output "Nenhum segredo próximo de expiração encontrado."
    exit 0
}

# ========================
# ENVIO DE E-MAIL VIA GRAPH API
# ========================
$recipients = @()
foreach ($email in $notificationEmails) {
    $recipients += @{ EmailAddress = @{ Address = $email } }
}

$emailMessage = @{
    Message = @{
        Subject = $emailSubject
        Body = @{
            ContentType = "HTML"
            Content     = $emailBody
        }
        ToRecipients = $recipients
    }
    SaveToSentItems = $false
}

$sendEmailUri = "https://graph.microsoft.com/v1.0/users/$senderEmail/sendMail"
Invoke-RestMethod -Method POST -Uri $sendEmailUri -Headers @{ Authorization = "Bearer $token" } `
    -Body ($emailMessage | ConvertTo-Json -Depth 10 -Compress) -ContentType "application/json"

Write-Output "Alerta enviado com sucesso para: $($notificationEmails -join ', ')"


