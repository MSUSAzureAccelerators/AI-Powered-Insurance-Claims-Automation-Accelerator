param (
    [Parameter(Mandatory=$true)]
    [string]$uniqueName = "482527", 
    [string]$subscriptionId = "349712bb-310c-40f9-8bf0-dd71c7cfe61c",
    [string]$location = "eastus",
	[string]$appId = ""
)

Function Pause ($Message = "Press any key to continue...") {
   # Check if running in PowerShell ISE
   If ($psISE) {
      # "ReadKey" not supported in PowerShell ISE.
      # Show MessageBox UI
      $Shell = New-Object -ComObject "WScript.Shell"
      Return
   }
 
   $Ignore =
      16,  # Shift (left or right)
      17,  # Ctrl (left or right)
      18,  # Alt (left or right)
      20,  # Caps lock
      91,  # Windows key (left)
      92,  # Windows key (right)
      93,  # Menu key
      144, # Num lock
      145, # Scroll lock
      166, # Back
      167, # Forward
      168, # Refresh
      169, # Stop
      170, # Search
      171, # Favorites
      172, # Start/Home
      173, # Mute
      174, # Volume Down
      175, # Volume Up
      176, # Next Track
      177, # Previous Track
      178, # Stop Media
      179, # Play
      180, # Mail
      181, # Select Media
      182, # Application 1
      183  # Application 2
 
   Write-Host -NoNewline $Message -ForegroundColor Red
   While ($Null -eq $KeyInfo.VirtualKeyCode  -Or $Ignore -Contains $KeyInfo.VirtualKeyCode) {
      $KeyInfo = $Host.UI.RawUI.ReadKey("NoEcho, IncludeKeyDown")
   }
}

Write-Host Logging in... -ForegroundColor Green
Connect-AzAccount
$ScriptRoot = 'D:\repos\fsihack\deploy'
$resourceGroupName = 'FSIUC3-' + $uniqueName
$storageAccountName = 'adls' + $uniqueName
Write-Host RGName $resourceGroupName -ForegroundColor Green
Write-Host StorageAccount $storageAccountName -ForegroundColor Green
$storageAccount = Get-AzStorageAccount `
		-ResourceGroupName $resourceGroupName `
		-AccountName $storageAccountName
$storageContext = $storageAccount.Context
$storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -AccountName $storageAccountName).Value[0]
$CorsRules = (@{
	AllowedHeaders  = @("*");
	AllowedOrigins  = @("*");
	MaxAgeInSeconds = 0;
	AllowedMethods  = @("Delete", "Get", "Head", "Merge", "Put", "Post", "Options", "Patch");
	ExposedHeaders  = @("*");
})
Write-Host Setting Cors Rule -ForegroundColor Green
Set-AzStorageCORSRule -ServiceType Blob -CorsRules $CorsRules -Context $storageContext
$storageContainerFormsImages = "images"
$storageContainerFormsInsurance = "insurance"
$storageContainerFormsProcessing = "processing"
$storageContainerProcessSucceeded = "succeeded"
$storageContainerProcessUpload = "upload"
$storageContainerNames = @($storageContainerFormsImages, $storageContainerFormsInsurance, $storageContainerFormsProcessing, $storageContainerProcessSucceeded, $storageContainerProcessUpload)
Write-Host Create Containers -ForegroundColor Green
foreach ($containerName in $storageContainerNames) {
   new-AzStoragecontainer `
				-Name $containerName `
				-Context $storageContext `
				-Permission container
}

Write-Host Create Cosmos Account -ForegroundColor Green
$cosmosAccountName = "cdb" + $uniqueName
$cosmosDatabaseName = "fsihack"
$cosmosClaimsContainer = "claims"
$cosmosDatabaseProperties = @{
	"resource" = @{ "id" = $cosmosDatabaseName };
	"options"  = @{ "Throughput" = 400 }
} 
$cosmosLocations = @(
	@{ "locationName" = "East US"; "failoverPriority" = 0 }
)
$consistencyPolicy = @{
	"defaultConsistencyLevel" = "BoundedStaleness";
	"maxIntervalInSeconds"    = 300;
	"maxStalenessPrefix"      = 100000
}
$cosmosProperties = @{
	"databaseAccountOfferType"     = "standard";
	"locations"                    = $cosmosLocations;
	"consistencyPolicy"            = $consistencyPolicy;
	"enableMultipleWriteLocations" = "true"
}
New-AzResource `
	-ResourceType "Microsoft.DocumentDb/databaseAccounts" `
	-ApiVersion "2015-04-08" `
	-ResourceGroupName $resourceGroupName `
	-Location $location `
	-Name $cosmosAccountName `
	-PropertyObject ($cosmosProperties) `
	-Force
$cosmosResourceName = $cosmosAccountName + "/sql/" + $cosmosDatabaseName
$currentCosmosDb = Get-AzResource `
		-ResourceType "Microsoft.DocumentDb/databaseAccounts/apis/databases" `
		-ResourceGroupName $resourceGroupName `
		-Name $cosmosResourceName 
		
if ($null -eq $currentCosmosDb.Name) {
	New-AzResource `
		-ResourceType "Microsoft.DocumentDb/databaseAccounts/apis/databases" `
		-ApiVersion "2015-04-08" `
		-ResourceGroupName $resourceGroupName `
		-Name $cosmosResourceName `
		-PropertyObject ($cosmosDatabaseProperties) `
		-Force
}
Write-Host Create Cosmos Container -ForegroundColor Green
$cosmosContainerNames = @($cosmosClaimsContainer)
foreach ($containerName in $cosmosContainerNames) {
	$containerResourceName = $cosmosAccountName + "/sql/" + $cosmosDatabaseName + "/" + $containerName
	 $cosmosContainerProperties = @{
			"resource" = @{
				"id"           = $containerName; 
				"partitionKey" = @{
					"paths" = @("/claimId"); 
					"kind"  = "Hash"
				}; 
			};
			"options"  = @{ }
		}
		New-AzResource `
				-ResourceType "Microsoft.DocumentDb/databaseAccounts/apis/databases/containers" `
				-ApiVersion "2015-04-08" `
				-ResourceGroupName $resourceGroupName `
				-Name $containerResourceName `
				-PropertyObject $cosmosContainerProperties `
				-Force 
}

Write-Host Create Form Recognizer Containers and upload data -ForegroundColor Green
$trainingFilePath = "$ScriptRoot\Train\"
$testFilePath = "$ScriptRoot\Test\"

$folders = Get-ChildItem $trainingFilePath
$formContainerName = "train"
New-AzStoragecontainer `
	-Name $formContainerName `
	-Context $storageContext  `
	-Permission container
foreach ($folder in $folders) {
	$files = Get-ChildItem $folder
	foreach($file in $files){
		$filePath = $trainingFilePath + $folder.Name + '\' + $file.Name
		$blobFileName = $folder.Name + '\' + $file.Name
		Write-Host Upload File $filePath -ForegroundColor Green
		Set-AzStorageBlobContent `
			-File $filePath `
			-Container $formContainerName `
			-Blob $blobFileName `
			-Context $storageContext `
			-Force
		
	}
}
$folders = Get-ChildItem $testFilePath
$formContainerName = "test"
New-AzStoragecontainer `
	-Name $formContainerName `
	-Context $storageContext  `
	-Permission container
foreach ($folder in $folders) {
	$files = Get-ChildItem $folder
	foreach($file in $files){
		$filePath = $testFilePath + $folder.Name + '\' + $file.Name
		$blobFileName = $folder.Name + '\' + $file.Name
		Write-Host Upload File $filePath -ForegroundColor Green
		Set-AzStorageBlobContent `
			-File $filePath `
			-Container $formContainerName `
			-Blob $blobFileName `
			-Context $storageContext `
			-Force
		
	}
}
Write-Host Create LUIS model -ForegroundColor Green
$luisAuthoringName = 'luis' + $uniqueName + '-author'
$luisAuthoringEndpoint =  (Get-AzCognitiveServicesAccount -ResourceGroupName $resourceGroupName -Name $luisAuthoringName).Endpoint		
$luisAuthoringSubscriptionKey =  (Get-AzCognitiveServicesAccountKey -ResourceGroupName $resourceGroupName -Name $luisAuthoringName).Key1		
$luisPredictionName = 'luis' + $uniqueName + '-pred'
$luisAppImportUrl = $luisAuthoringEndpoint + "luis/authoring/v3.0-preview/apps/import"

$luisHeader = @{
	"Ocp-Apim-Subscription-Key" = $luisAuthoringSubscriptionKey
}
$trainingLuisFilePath = "$ScriptRoot\luis\"

$files = Get-ChildItem $trainingLuisFilePath
foreach($file in $files){
	$fileWithExtension = $trainingLuisFilePath + $file.Name.toLower()
	$luisApplicationName = (Get-Item $fileWithExtension).Basename
	$luisApplicationFilePath = $trainingLuisFilePath + $file.Name
	$luisApplicationTemplate = Get-Content $luisApplicationFilePath
	$appVersion = '0.1'
	
	$luisAppResponse = Invoke-RestMethod -Method Post `
				-Uri $luisAppImportUrl -ContentType "application/json" `
				-Headers $luisHeader `
				-Body $luisApplicationTemplate
	$luisAppId = $luisAppResponse
	$luisTrainUrl = $luisAuthoringEndpoint + "luis/authoring/v3.0-preview/apps/" + $luisAppId + "/versions/" + $appVersion + "/train"
	
	$luisAppTrainResponse = Invoke-RestMethod -Method Post `
				-Uri $luisTrainUrl `
				-Headers $luisHeader
	
	Start-Sleep -s 10
	$luisAppTrainResponse = Invoke-RestMethod -Method Get `
				-Uri $luisTrainUrl `
				-Headers $luisHeader

	$publishJsonBody = "{
		'versionId': '$appVersion',
		'isStaging': false,
		'directVersionPublish': false
	}"

	$luisPublihUrl = $luisAuthoringEndpoint + "luis/authoring/v3.0-preview/apps/" + $luisAppId + "/publish"
	$luisAppPublishResponse = Invoke-RestMethod -Method Post `
				-Uri $luisPublihUrl -ContentType "application/json" `
				-Headers $luisHeader `
				-Body $luisApplicationTemplate
	$luisAppPublishResponse
}
$pauseMessage = 'Go to Azure resource group ' + $resourceGroupName + 'and add prediction resource for Luis model'
Pause $pauseMessage
$azureBlobApiConnectionName = "azureblob"
$azureblobTemplateFilePath = "$ScriptRoot\templates\azureblob-template.json"
$azureblobParametersFilePath = "$ScriptRoot\templates\azureblob-parameters.json"
$azureblobParametersTemplate = Get-Content $azureblobParametersFilePath | ConvertFrom-Json
$azureblobParameters = $azureblobParametersTemplate.parameters
$azureblobParameters.subscription_id.value = $subscriptionId
$azureblobParameters.storage_account_name.value = $storageAccountName
$azureblobParameters.storage_access_key.value = $storageAccountKey
$azureblobParameters.location.value = $location
$azureblobParameters.connections_azureblob_name.value = $azureBlobApiConnectionName
$azureblobParametersTemplate | ConvertTo-Json | Out-File $azureblobParametersFilePath
Write-Host Create API Connections -ForegroundColor Green
New-AzResourceGroupDeployment `
	-ResourceGroupName $resourceGroupName `
	-Name $azureBlobApiConnectionName `
	-TemplateFile $azureblobTemplateFilePath `
	-TemplateParameterFile $azureblobParametersFilePath
	

$azurecustVisionApiConnectionName = "cognitiveservicescustomvision"
$azurecustVisionTemplateFilePath = "$ScriptRoot\templates\customvision-template.json"
$azurecustVisionParametersFilePath = "$ScriptRoot\templates\customvision-parameters.json"
$azurecustVisionParametersTemplate = Get-Content $azurecustVisionParametersFilePath | ConvertFrom-Json
$azurecustVisionParameters = $azurecustVisionParametersTemplate.parameters
$azurecustVisionParameters.subscription_id.value = $subscriptionId
$azurecustVisionParameters.predictive_url.value = 'https://customvis481808prediction.cognitiveservices.azure.com/'
$azurecustVisionParameters.customvision_key.value = 'b7959e606d4049ecb43268174d77d005'
$azurecustVisionParameters.location.value = $location
$azurecustVisionParameters.connections_customvision_name.value = $azurecustVisionApiConnectionName
$azurecustVisionParametersTemplate | ConvertTo-Json | Out-File $azurecustVisionParametersFilePath

New-AzResourceGroupDeployment `
	-ResourceGroupName $resourceGroupName `
	-Name $azurecustVisionApiConnectionName `
	-TemplateFile $azurecustVisionTemplateFilePath `
	-TemplateParameterFile $azurecustVisionParametersFilePath

$azureformRecognizerApiConnectionName = "formrecognizer"
$azureformRecognizerTemplateFilePath = "$ScriptRoot\templates\formrecognizer-template.json"
$azureformRecognizerParametersFilePath = "$ScriptRoot\templates\formrecognizer-parameters.json"
$azureformRecognizerParametersTemplate = Get-Content $azureformRecognizerParametersFilePath | ConvertFrom-Json
$azureformRecognizerParameters = $azureformRecognizerParametersTemplate.parameters
$azureformRecognizerParameters.subscription_id.value = $subscriptionId
$azureformRecognizerParameters.predictive_url.value = 'https://formrec481808subdomain.cognitiveservices.azure.com/'
$azureformRecognizerParameters.formrecognizer_key.value = '1c673b9bd9b8464492c18768da270ed2'
$azureformRecognizerParameters.location.value = $location
$azureformRecognizerParameters.connections_formrecognizer_name.value = $azureformRecognizerApiConnectionName
$azureformRecognizerParametersTemplate | ConvertTo-Json | Out-File $azureformRecognizerParametersFilePath
New-AzResourceGroupDeployment `
	-ResourceGroupName $resourceGroupName `
	-Name $azureformRecognizerApiConnectionName `
	-TemplateFile $azureformRecognizerTemplateFilePath `
	-TemplateParameterFile $azureformRecognizerParametersFilePath
	
$azuredocumentDbApiConnectionName = "documentdb"
$azuredocumentDbTemplateFilePath = "$ScriptRoot\templates\cosmosdb-template.json"
$azuredocumentDbParametersFilePath = "$ScriptRoot\templates\cosmosdb-parameters.json"
$azuredocumentDbParametersTemplate = Get-Content $azuredocumentDbParametersFilePath | ConvertFrom-Json
$azuredocumentDbParameters = $azuredocumentDbParametersTemplate.parameters
$azuredocumentDbParameters.subscription_id.value = $subscriptionId
$azuredocumentDbParameters.cosmosdb_key.value = 'JGxrsh3WKvKD9JPN1Hu2rQzvvYWctLnlJNoNWC3BbKHGWdpKLsAfbk1cUeQbMktkMUXynT0ShmTkHkNdIFax1A=='
$azuredocumentDbParameters.location.value = $location
$azuredocumentDbParameters.connections_cosmosdb_name.value = $azuredocumentDbApiConnectionName
$azuredocumentDbParameters.cosmosdb_account_name.value = $cosmosAccountName
$azuredocumentDbParametersTemplate | ConvertTo-Json | Out-File $azuredocumentDbParametersFilePath

New-AzResourceGroupDeployment `
	-ResourceGroupName $resourceGroupName `
	-Name $azuredocumentDbApiConnectionName `
	-TemplateFile $azuredocumentDbTemplateFilePath `
	-TemplateParameterFile $azuredocumentDbParametersFilePath
$pauseMessage = 'Go to Azure resource group ' + $resourceGroupName + 'and authorize all api connection connection, save and continue here'
Pause $pauseMessage
Write-Host Deploy Logic app -ForegroundColor Green
$logicAppName = 'logicapp' + $uniqueName
$pauseMessage = 'Go to Azure resource group ' + $resourceGroupName + 'and delete logicapp ' + $logicAppName
Pause $pauseMessage
$logicAppTemplateFilePath = "$ScriptRoot\templates\fsihacklapp-template.json"
$logicAppParametersFilePath = "$ScriptRoot\templates\fsihacklapp-parameters.json"
$azureblobResourceid = Get-AzResource `
	-ResourceGroupName $resourceGroupName `
	-Name $azureBlobApiConnectionName
$azurecustVisionResourceid  = Get-AzResource `
	-ResourceGroupName $resourceGroupName `
	-Name $azurecustVisionApiConnectionName 
$azureformRecognizerResourceid  = Get-AzResource `
	-ResourceGroupName $resourceGroupName `
	-Name $azureformRecognizerApiConnectionName
$azuredocumentDbResourceid  = Get-AzResource `
	-ResourceGroupName $resourceGroupName `
	-Name $azuredocumentDbApiConnectionName	

$logicAppParametersTemplate = Get-Content $logicAppParametersFilePath | ConvertFrom-Json
$logicAppParameters = $logicAppParametersTemplate.parameters
$logicAppParameters.workflows_fsihacklogicapp_name.value = $logicAppName
$logicAppParameters.subscription_id.value = $subscriptionId
$logicAppParameters.resource_group.value = $resourceGroupName
$logicAppParameters.location.value = $location
$logicAppParameters.connections_azureblob_externalid.value = $azureblobResourceid.Id
$logicAppParameters.connections_cognitiveservicescustomvision_externalid.value = $azurecustVisionResourceid.Id
$logicAppParameters.connections_formrecognizer_externalid.value = $azureformRecognizerResourceid.Id
$logicAppParameters.connections_documentdb_externalid.value = $azuredocumentDbResourceid.Id
$logicAppParametersTemplate | ConvertTo-Json | Out-File $logicAppParametersFilePath

New-AzResourceGroupDeployment `
		-ResourceGroupName $resourceGroupName `
		-Name $logicAppName `
		-TemplateFile $logicAppTemplateFilePath `
		-TemplateParameterFile $logicAppParametersFilePath
Write-Host Deploy Web app -ForegroundColor Green
$appInsightName = "asaappinsights" + $uniqueName
$botName = "od" + $uniqueName + "bot"
$appInsightInstrumentationKey = (Get-AzApplicationInsights -ResourceGroupName $resourceGroupName -Name $appInsightName).InstrumentationKey
$botWebApiName = "od" + $uniqueName + 'webapp'
$appServicePlanName = "app-plan" + $uniqueName
$webApiSettings = @{
		serverFarmId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Web/serverFarms/$AppServicePlanName";
		alwaysOn     = $True;
	}
$currentUiWebApi = Get-AzResource `
	-ResourceGroupName $resourceGroupName `
	-ResourceName $botWebApiName 
if ( $currentUiWebApi.Name -eq $null )
{
 New-AzResource `
		-ResourceGroupName $resourceGroupName `
		-Location $location `
		-ResourceName $botWebApiName `
		-ResourceType "microsoft.web/sites" `
		-Kind "app" `
		-Properties $webApiSettings `
		-Force
}
$webAppSettings = @{
	APPINSIGHTS_INSTRUMENTATIONKEY = $appInsightInstrumentationKey;
}

Set-AzWebApp `
	-Name $botWebApiName `
	-ResourceGroupName $resourceGroupName `
	-AppSettings $webAppSettings 
$endPointName = "https://" + $botWebApiName + ".azurewebsites.net/api/messages"
$botTemplateFilePath = "$ScriptRoot\templates\azurebot-template.json"
$botParametersFilePath = "$ScriptRoot\templates\azurebot-parameters.json"
$botParametersTemplate = Get-Content $botParametersFilePath | ConvertFrom-Json
$botParameters = $botParametersTemplate.parameters
$botParameters.botservice_endpoint.value = $endPointName
$botParameters.botservice_name.value = $botName
$botParameters.msaappId.value = $appId
$botParametersTemplate | ConvertTo-Json | Out-File $botParametersFilePath
Write-Host Deploy Bot Service -ForegroundColor Green
New-AzResourceGroupDeployment `
	-ResourceGroupName $resourceGroupName `
	-Name $botName `
	-TemplateFile $botTemplateFilePath `
	-TemplateParameterFile $botParametersFilePath
Logout-AzAccount