# The IP list from Cloudflare(China), updates at least every 30 days
# The runbook runs every day, to compare the list with yesterday's
# And sends out notification emails once change is detected
# So the NSG/Firewall which allows the IP list, will need to be updated accordingly

# Pre-created resources: 
#  -- Storage account and container
#  -- Automation Account credentials for SMTP authentication
#  -- System identity for automation account to have RW access of the storage account 

$AzureSubscriptionName = "SubscriptionName"  # Subscription NAME
$AzureStorageAccountName = "StorageAccountName" # STORAGE ACCOUNT NAME
$ContainerName = "StorageAccount-ContainerName" # Container Name

# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave -Scope Process

# Connect to Azure with system-assigned managed identity
try {
        $AzureContext = (Connect-AzAccount -EnvironmentName AzureChinaCloud -Identity).context
    }
catch{
        Write-Output "There is no system-assigned user identity. Aborting."; 
        exit
    }

# Set and store context
$AzureContext = Set-AzContext -SubscriptionName $AzureSubscriptionName 
$StorageAcctContext = New-AzStorageContext -StorageAccountName $AzureStorageAccountName -UseConnectedAccount

# Set the temporary location and names for the files
$filePath = "c:\temp\"
$dateYesterday = (Get-Date).AddDays(-1).tostring("yyyyMMdd")
$dateToday = (Get-Date).tostring("yyyyMMdd")

$fileToday=$filePath+"cfiplist_$dateToday.json"
$fileYesterday=$filePath+"cfiplist_$dateYesterday.json"
$attachmentFile= $filePath+"ipv4_$dateToday.txt"
$downloadUri = "https://api.cloudflare.com/client/v4/ips?networks=jdcloud"

# download the ip list from CloudFlare
Invoke-WebRequest -Uri $downloadUri -OutFile $fileToday

# Create an empty file for attachement
New-Item -Path $attachmentFile -Force

# Upload today's file to Blob storage
Set-AzStorageBlobContent -File $fileToday -Container $ContainerName -Blob "cfiplist_$dateToday.json" -Context $StorageAcctContext -Force
Write-Output "Uploaded today's file cfiplist_$dateToday.json to blob storage."
# Download yesterday's file for comparison
Get-AzStorageBlobContent -Container $ContainerName -Blob "cfiplist_$dateYesterday.json" -Destination $filePath -Context $StorageAcctContext -Force
Write-Output "Downloaded yesterday's file cfiplist_$dateYesterday.json."

# Extract only the IPv4 lists from today's file
$json1 = Get-Content $fileToday -raw| ConvertFrom-Json
$global_ipv4_today=$json1.result.ipv4_cidrs
$jdcloud_ipv4_today=$json1.result.jdcloud_cidrs | Where-Object { $_ -match '(\d{1,3}\.){3}\d{1,3}\/\d{1,2}' }

# Extract only the IPv4 lists from yesterday's file
$json2 = Get-Content $fileYesterday -raw| ConvertFrom-Json
$global_ipv4_yesterday=$json2.result.ipv4_cidrs 
$jdcloud_ipv4_yesterday=$json2.result.jdcloud_cidrs | Where-Object { $_ -match '(\d{1,3}\.){3}\d{1,3}\/\d{1,2}' }

# Compare today's list with yesterday. 
try{
    $diff1=Compare-Object -ReferenceObject $global_ipv4_today -DifferenceObject $global_ipv4_yesterday
 }
 catch{
    Write-Error "$_."
 }

 try{
    $diff2=Compare-Object -ReferenceObject $jdcloud_ipv4_today -DifferenceObject $jdcloud_ipv4_yesterday
 }
 catch{
    Write-Error "$_."
 }

# define the variables for sending email
	$recipient = "recipient@example.com"
	$emailFrom = "sender@example.com"
	$emailCC = @("cc1@example.com","cc2@example.com")
	$smtpServer = "smtp.qq.com"
	$smtpPort = 587
	$aaCred="IPListCheck-email-credential"    #credentials provided in Automation Account
	$emailSubject="[Azure Automation]: CloudFlare IP List Checker"
	$emailBody = @"
	This is a mail sending from Azure Automation Account -- to compare the latest Cloudflare IPV4 list with yesterday's.
	
	Email is only sent when change is detected. 
	
"@
	
	
	# Get credentials from Automation Account for SMTP authentication
	try{
        $smtpCredential = Get-AutomationPSCredential -Name $aaCred
	}
	catch{
        Write-Output "Error in getting the SMTP credential."
	}

# if there is any change, place the new IPv4 CIDR in the email attachment and send the email
 if ($diff1 -or $diff2){
	if ($diff1){
		Write-Output "Global IPv4 CIDR Changes found."
		$ipv4_cidr = $global_ipv4_today -join ","
		Add-Content -Path $attachmentFile -Value "Global IPv4 CIDR: `n$ipv4_cidr"
	}
	if($diff2){
		Write-Output "JD Cloud IPv4 CIDR Changes found."
		$ipv4_cidr = $jdcloud_ipv4_today -join ","
		Add-Content -Path $attachmentFile -Value "JD Cloud IPv4 CIDR: `n$ipv4_cidr"
	}
	try{
        Send-MailMessage -Subject $emailSubject -Body $emailBody -Attachments $attachmentFile -To $recipient -Cc $emailCC -From $emailFrom -SmtpServer $smtpServer -Credential $smtpCredential -Port $smtpPort -UseSsl -WarningAction SilentlyContinue;
        Write-Output "Changes sent via email."
    }
    catch{
        Write-Error "$_."
    }
 }else{
	Write-Output "No change found."
 }
