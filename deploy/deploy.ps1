##################################################################
#                                                                #
#   Setup Script                                                 #
#                                                                #
#   Spins up azure resources for RPA solution using MS Services. #
##################################################################


#----------------------------------------------------------------#
#   Parameters                                                   #
#----------------------------------------------------------------#
param (
    [Parameter(Mandatory=$true)]
    [string]$uniqueName = "default", 
    [string]$subscriptionId = "default",
    [string]$location = "default",
	[string]$resourceGroupName = "default"
)
$cognitiveSearch = 'true'
$deployWebUi = 'true'

if($uniqueName -eq "default")
{
    Write-Error "Please specify a unique name."
    break;
}

if($uniqueName.Length -gt 17)
{
    Write-Error "The unique name is too long. Please specify a name with less than 17 characters."
}

if($uniqueName -Match "-")
{
	Write-Error "The unique name should not contain special characters"
}

if($location -eq "default")
{
	while ($TRUE) {
		try {
			$location = Read-Host -Prompt "Input Location(westus, eastus, centralus, southcentralus): "
			break  
		}
		catch {
				Write-Error "Please specify a resource group name."
		}
	}
}

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

$uniqueName = $uniqueName.ToLower();

# prefixes
$prefix = $uniqueName

if ( $resourceGroupName -eq 'default' ) {
	$resourceGroupName = $prefix
}

#$ScriptRoot = "C:\Projects\Repos\msrpa\deploy\scripts"
$outArray = New-Object System.Collections.ArrayList($null)

if ($ScriptRoot -eq "" -or $null -eq $ScriptRoot ) {
	$ScriptRoot = (Get-Location).path
}

$outArray.Add("v_prefix=$prefix")
$outArray.Add("v_resourceGroupName=$resourceGroupName")
$outArray.Add("v_location=$location")

#----------------------------------------------------------------#
#   Setup - Azure Subscription Login							 #
#----------------------------------------------------------------#
$ErrorActionPreference = "Stop"
#Install-Module AzTable -Force

# Sign In
Write-Host Logging in... -ForegroundColor Green
Connect-AzAccount
az login

if($subscriptionId -eq "default"){
	# Set Subscription Id
	while ($TRUE) {
		try {
			$subscriptionId = Read-Host -Prompt "Input subscription Id"
			break  
		}
		catch {
			Write-Host Invalid subscription Id. -ForegroundColor Green `n
		}
	}
}

$outArray.Add("v_subscriptionId=$subscriptionId")
$context = Get-AzSubscription -SubscriptionId $subscriptionId
Set-AzContext @context

Enable-AzContextAutosave -Scope CurrentUser
$index = 0
$numbers = "123456789"
foreach ($char in $subscriptionId.ToCharArray()) {
    if ($numbers.Contains($char)) {
        break;
    }
    $index++
}
$id = $subscriptionId.Substring($index, $index + 5)


Install-Module Az.Search -Force
Install-Module -Name Az.BotService -Force
Install-Module AzureAD -Force
Import-Module AzureAD
#----------------------------------------------------------------#
#   Step 1 - Register Resource Providers and Resource Group		 #
#----------------------------------------------------------------#

$resourceProviders = @(
    "microsoft.documentdb",
    "microsoft.insights",
    "microsoft.search",
    "microsoft.storage",
    "microsoft.logic",
    "microsoft.web"
)
	
Write-Host Registering resource providers: -ForegroundColor Green`n 
foreach ($resourceProvider in $resourceProviders) {
    Write-Host - Registering $resourceProvider -ForegroundColor Green
	Register-AzResourceProvider `
            -ProviderNamespace $resourceProvider
}

# Create Resource Group 
Write-Host `nCreating Resource Group $resourceGroupName"..." -ForegroundColor Green `n
try {
		Get-AzResourceGroup `
			-Name $resourceGroupName `
			-Location $location `
	}
catch {
		New-AzResourceGroup `
			-Name $resourceGroupName `
			-Location $location `
			-Force
	}

#----------------------------------------------------------------#
#   Step 2 - Storage Account & Containers						 #
#----------------------------------------------------------------#
# Create Storage Account
# storage resources
#$storageAccountName = $prefix + $id + "stor";
$storageAccountName = $prefix + "sa";
$storageContainerFormsImages = "images"
$storageContainerFormsInsurance = "insurance"
$storageContainerFormsProcessing = "processing"
$storageContainerProcessSucceeded = "succeeded"
$storageContainerProcessUpload = "upload"

$outArray.Add("v_storageAccountName=$storageAccountName")
$outArray.Add("v_storageContainerFormsImages=$storageContainerFormsImages")
$outArray.Add("v_storageContainerFormsInsurance=$storageContainerFormsInsurance")
$outArray.Add("v_storageContainerFormsProcessing=$storageContainerFormsProcessing")
$outArray.Add("v_storageContainerProcessSucceeded=$storageContainerProcessSucceeded")
$outArray.Add("v_storageContainerProcessSucceeded=$storageContainerProcessUpload")


Write-Host Creating storage account... -ForegroundColor Green

try {
        $storageAccount = Get-AzStorageAccount `
            -ResourceGroupName $resourceGroupName `
            -AccountName $storageAccountName
    }
    catch {
        $storageAccount = New-AzStorageAccount `
            -AccountName $storageAccountName `
            -ResourceGroupName $resourceGroupName `
            -Location $location `
            -SkuName Standard_LRS `
            -Kind StorageV2 
    }
$storageAccount
$storageContext = $storageAccount.Context
Start-Sleep -s 1

Enable-AzStorageStaticWebsite `
	-Context $storageContext `
	-IndexDocument "index.html" `
	-ErrorDocument404Path "error.html"

$CorsRules = (@{
		AllowedHeaders  = @("*");
		AllowedOrigins  = @("*");
		MaxAgeInSeconds = 0;
		AllowedMethods  = @("Delete", "Get", "Head", "Merge", "Put", "Post", "Options", "Patch");
		ExposedHeaders  = @("*");
	})
Set-AzStorageCORSRule -ServiceType Blob -CorsRules $CorsRules -Context $storageContext


# Create Storage Containers
Write-Host Creating blob containers... -ForegroundColor Green
$storageContainerNames = @($storageContainerFormsImages, $storageContainerFormsInsurance, $storageContainerFormsProcessing, $storageContainerProcessSucceeded, $storageContainerProcessUpload)
foreach ($containerName in $storageContainerNames) {
	try {
		new-AzStoragecontainer `
                -Name $containerName `
                -Context $storageContext `
                -Permission container
    }
    catch {
    }
}

# Get Account Key and connection string
$storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -AccountName $storageAccountName).Value[0]
$storageAccountConnectionString = 'DefaultEndpointsProtocol=https;AccountName=' + $storageAccountName + ';AccountKey=' + $storageAccountKey + ';EndpointSuffix=core.windows.net' 

$outArray.Add("v_storageAccountKey=$storageAccountKey")
$outArray.Add("v_storageAccountConnectionString=$storageAccountConnectionString")

#----------------------------------------------------------------#
#   Step 3 - Cognitive Services									 #
#----------------------------------------------------------------#
# Create Form Recognizer Account

# cognitive services resources
#$formRecognizerName = $prefix + $id + "formreco"
$formRecognizerName = $prefix + "frcs"
$outArray.Add("v_formRecognizerName=$formRecognizerName")

Write-Host Creating Form Recognizer service... -ForegroundColor Green

New-AzCognitiveServicesAccount `
		-ResourceGroupName $resourceGroupName `
		-Name $formRecognizerName `
		-Type FormRecognizer `
		-SkuName S0 `
		-Location $location

# Get Key and Endpoint
$formRecognizerEndpoint =  (Get-AzCognitiveServicesAccount -ResourceGroupName $resourceGroupName -Name $formRecognizerName).Endpoint		
$formRecognizerSubscriptionKey =  (Get-AzCognitiveServicesAccountKey -ResourceGroupName $resourceGroupName -Name $formRecognizerName).Key1		
$outArray.Add("v_formRecognizerEndpoint=$formRecognizerEndpoint")
$outArray.Add("v_formRecognizerSubscriptionKey=$formRecognizerSubscriptionKey")


# Create Cognitive Services ( All in one )

$luisAuthoringName = $prefix + "lacs"
$outArray.Add("v_luisAuthoringName=$luisAuthoringName")
Write-Host Creating Luis Authoring Service... -ForegroundColor Green

New-AzCognitiveServicesAccount `
		-ResourceGroupName $resourceGroupName `
		-Name $luisAuthoringName `
		-Type LUIS.Authoring `
		-SkuName F0 `
		-Location 'westus'

# Get Key and Endpoint
$luisAuthoringEndpoint =  (Get-AzCognitiveServicesAccount -ResourceGroupName $resourceGroupName -Name $luisAuthoringName).Endpoint		
$luisAuthoringSubscriptionKey =  (Get-AzCognitiveServicesAccountKey -ResourceGroupName $resourceGroupName -Name $luisAuthoringName).Key1		
$outArray.Add("v_luisAuthoringEndpoint=$luisAuthoringEndpoint")
$outArray.Add("v_luisAuthoringSubscriptionKey=$luisAuthoringSubscriptionKey")

$luisPredictionName = $prefix + "lpcs"
$outArray.Add("v_luisAuthoringName=$luisPredictionName")
Write-Host Creating Luis Prediction Service... -ForegroundColor Green

New-AzCognitiveServicesAccount `
		-ResourceGroupName $resourceGroupName `
		-Name $luisPredictionName `
		-Type LUIS `
		-SkuName F0 `
		-Location 'westus'

# Get Key and Endpoint
$luisPredictionEndpoint =  (Get-AzCognitiveServicesAccount -ResourceGroupName $resourceGroupName -Name $luisPredictionName).Endpoint		
$luisPredictionSubscriptionKey =  (Get-AzCognitiveServicesAccountKey -ResourceGroupName $resourceGroupName -Name $luisPredictionName).Key1		
$outArray.Add("v_luisAuthoringEndpoint=$luisPredictionEndpoint")
$outArray.Add("v_luisAuthoringSubscriptionKey=$luisPredictionSubscriptionKey")


# Create Custom Vision Training Cognitive service
#$customVisionTrain = $prefix + $id + "cvtrain"
$customVisionTrain = $prefix + "cvtraincs"
$outArray.Add("v_customVisionTrain=$customVisionTrain")

Write-Host Creating Cognitive service Custom Vision Training ... -ForegroundColor Green


New-AzCognitiveServicesAccount `
		-ResourceGroupName $resourceGroupName `
		-Name $customVisionTrain `
		-Type CustomVision.Training `
		-SkuName S0 `
		-Location $location

# Get Key and Endpoint
$customVisionTrainEndpoint =  (Get-AzCognitiveServicesAccount -ResourceGroupName $resourceGroupName -Name $customVisionTrain).Endpoint		
$customVisionTrainSubscriptionKey =  (Get-AzCognitiveServicesAccountKey -ResourceGroupName $resourceGroupName -Name $customVisionTrain).Key1		
$outArray.Add("v_customVisionTrainEndpoint=$customVisionTrainEndpoint")
$outArray.Add("v_customVisionTrainSubscriptionKey=$customVisionTrainSubscriptionKey")

# Create Custom Vision Prediction Cognitive service
$customVisionPredict = $prefix + "cvpredictcs"
$outArray.Add("v_customVisionPredict=$customVisionPredict")

Write-Host Creating Cognitive service Custom Vision Prediction ... -ForegroundColor Green


New-AzCognitiveServicesAccount `
		-ResourceGroupName $resourceGroupName `
		-Name $customVisionPredict `
		-Type CustomVision.Prediction `
		-SkuName S0 `
		-Location $location


# Get Key and Endpoint
$customVisionPredictEndpoint =  (Get-AzCognitiveServicesAccount -ResourceGroupName $resourceGroupName -Name $customVisionPredict).Endpoint		
$customVisionPredictSubscriptionKey =  (Get-AzCognitiveServicesAccountKey -ResourceGroupName $resourceGroupName -Name $customVisionPredict).Key1		
$outArray.Add("v_customVisionPredictEndpoint=$customVisionPredictEndpoint")
$outArray.Add("v_customVisionPredictSubscriptionKey=$customVisionPredictSubscriptionKey")
		
#----------------------------------------------------------------#
#   Step 4 - App Service Plan 									 #
#----------------------------------------------------------------#

# Create App Service Plan
Write-Host Creating app service plan... -ForegroundColor Green
# app service plan
$appServicePlanName = $prefix + "asp"
$outArray.Add("v_appServicePlanName=$appServicePlanName")

#az functionapp create -g $resourceGroupName -n $appServicePlanName -s $storageAccountName -c $location

$currentApsName = Get-AzAppServicePlan -Name $appServicePlanName -ResourceGroupName $resourceGroupName
if ($currentApsName.Name -eq $null ) {
	New-AzAppServicePlan `
        -Name $appServicePlanName `
        -Location $location `
        -ResourceGroupName $resourceGroupName `
        -Tier Basic
}

#----------------------------------------------------------------#
#   Step 5 - Azure Search Service								 #
#----------------------------------------------------------------#
# Create Cognitive Search Service
Write-Host Creating Cognitive Search Service... -ForegroundColor Green
$cognitiveSearchName = $prefix + "azs"
$outArray.Add("v_cognitiveSearchName=$cognitiveSearchName")

$currentAzSearchName = Get-AzSearchService -ResourceGroupName $resourceGroupName -Name $cognitiveSearchName
if ($null -eq $currentAzSearchName.Name) {
	New-AzSearchService `
			-ResourceGroupName $resourceGroupName `
			-Name $cognitiveSearchName `
			-Sku "Basic" `
			-Location $location
}

$cognitiveSearchKey = (Get-AzSearchAdminKeyPair -ResourceGroupName $resourceGroupName -ServiceName $cognitiveSearchName).Primary
$cognitiveSearchEndPoint = 'https://' + $cognitiveSearchName + '.search.windows.net'
$outArray.Add("v_cognitiveSearchKey=$cognitiveSearchKey")
$outArray.Add("v_cognitiveSearchEndPoint=$cognitiveSearchEndPoint")

#----------------------------------------------------------------#
#   Step 6 - CosmosDb account, database and container			 #
#----------------------------------------------------------------#

# cosmos resources
$cosmosAccountName = $prefix + "cdbsql"
$cosmosDatabaseName = "fsihack"
$cosmosClaimsContainer = "claims"
$outArray.Add("v_cosmosAccountName=$cosmosAccountName")
$outArray.Add("v_cosmosDatabaseName=$cosmosDatabaseName")

# Create Cosmos SQL API Account
Write-Host Creating CosmosDB account... -ForegroundColor Green
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

Start-Sleep -s 30
		
# Create Cosmos Database
Write-Host Creating CosmosDB Database... -ForegroundColor Green
$cosmosDatabaseProperties = @{
    "resource" = @{ "id" = $cosmosDatabaseName };
    "options"  = @{ "Throughput" = 400 }
} 
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

# Create Cosmos Containers
Write-Host Creating CosmosDB Containers... -ForegroundColor Green
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

$cosmosEndPoint = (Get-AzResource -ResourceType "Microsoft.DocumentDb/databaseAccounts" `
     -ApiVersion "2015-04-08" -ResourceGroupName $resourceGroupName `
     -Name $cosmosAccountName | Select-Object Properties).Properties.documentEndPoint
$cosmosPrimaryKey = (Invoke-AzResourceAction -Action listKeys `
    -ResourceType "Microsoft.DocumentDb/databaseAccounts" -ApiVersion "2015-04-08" `
    -ResourceGroupName $resourceGroupName -Name $cosmosAccountName -Force).primaryMasterKey
$cosmosConnectionString = (Invoke-AzResourceAction -Action listConnectionStrings `
    -ResourceType "Microsoft.DocumentDb/databaseAccounts" -ApiVersion "2015-04-08" `
    -ResourceGroupName $resourceGroupName -Name $cosmosAccountName -Force).connectionStrings.connectionString[0]
$outArray.Add("v_cosmosEndPoint=$cosmosEndPoint")
$outArray.Add("v_cosmosPrimaryKey=$cosmosPrimaryKey")
$outArray.Add("v_cosmosConnectionString=$cosmosConnectionString")


#----------------------------------------------------------------#
#   Step 7 - Find all forms that needs training and upload		 #
#----------------------------------------------------------------#
# We currently have two level of "Folders" that we process
$trainingFilePath = "$ScriptRoot\Train\"
$testFilePath = "$ScriptRoot\Test\"
$outArray.Add("v_trainingFormFilePath=$trainingFilePath")

$trainingFormContainers = New-Object System.Collections.ArrayList($null)
$trainingFormContainers.Clear()
$testingFormContainers = New-Object System.Collections.ArrayList($null)
$testingFormContainers.Clear()

$folders = Get-ChildItem $trainingFilePath
$formContainerName = "train"
Write-Host Create Container $formContainerName	 -ForegroundColor Green		
try {
	New-AzStoragecontainer `
		-Name $formContainerName `
		-Context $storageContext  `
		-Permission container
}
catch 
{
}

foreach ($folder in $folders) {
	$trainingFormContainers.Add($formContainerName)
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
Write-Host Create Container $formContainerName	 -ForegroundColor Green	
try {
	New-AzStoragecontainer `
		-Name $formContainerName `
		-Context $storageContext  `
		-Permission container
}
catch
{
}
foreach ($folder in $folders) {
	$trainingFormContainers.Add($formContainerName)
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
#----------------------------------------------------------------#
#   Step 8 - Train LUIS Models						 			 #
#----------------------------------------------------------------#
# Train LUIS
Write-Host Luis Models... -ForegroundColor Green
$luisAppImportUrl = $luisAuthoringEndpoint + "luis/authoring/v3.0-preview/apps/import"
$outArray.Add("v_luisAppImportUrl=$luisAppImportUrl")

$luisHeader = @{
	"Ocp-Apim-Subscription-Key" = $luisAuthoringSubscriptionKey
}
$luisModels = @{ }
$luisModels.Clear()

$trainingLuisFilePath = "$ScriptRoot\luis\"

$files = Get-ChildItem $trainingLuisFilePath
foreach($file in $files){
	$fileWithExtension = $trainingLuisFilePath + $file.Name.toLower()
	$luisApplicationName = (Get-Item $fileWithExtension).Basename
	$luisApplicationFilePath = $trainingLuisFilePath + $file.Name
	$luisApplicationTemplate = Get-Content $luisApplicationFilePath
	$appVersion = '0.1'
	
	try
	{
	$luisAppResponse = Invoke-RestMethod -Method Post `
				-Uri $luisAppImportUrl -ContentType "application/json" `
				-Headers $luisHeader `
				-Body $luisApplicationTemplate
	$luisAppId = $luisAppResponse
	$luisModels[$luisApplicationName] = $luisAppId

	$luisTrainUrl = $luisAuthoringEndpoint + "luis/authoring/v3.0-preview/apps/" + $luisAppId + "/versions/" + $appVersion + "/train"
	
	Write-Host Training Luis Models... -ForegroundColor Green
	$luisAppTrainResponse = Invoke-RestMethod -Method Post `
				-Uri $luisTrainUrl `
				-Headers $luisHeader
	
	# Get Training Status
	# For now wait for 10 seconds
	Start-Sleep -s 10
	$luisAppTrainResponse = Invoke-RestMethod -Method Get `
				-Uri $luisTrainUrl `
				-Headers $luisHeader

	$publishJsonBody = "{
		'versionId': '$appVersion',
		'isStaging': false,
		'directVersionPublish': false
	}"

	#Publish the Model
	Write-Host Publish Luis Models... -ForegroundColor Green
	$luisPublihUrl = $luisAuthoringEndpoint + "luis/authoring/v3.0-preview/apps/" + $luisAppId + "/publish"
	$luisAppPublishResponse = Invoke-RestMethod -Method Post `
				-Uri $luisPublihUrl -ContentType "application/json" `
				-Headers $luisHeader `
				-Body $luisApplicationTemplate
	$luisAppPublishResponse
	}
	catch
	{
	}
}

#----------------------------------------------------------------#
#   Step 9 - Create API Connection and Deploy Logic app		 #
#----------------------------------------------------------------#
$azureBlobApiConnectionName = "azureblob"
$outArray.Add("v_azureBlobApiConnectionName = $azureBlobApiConnectionName")

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

Write-Host Deploying $azureBlobApiConnectionName"..." -ForegroundColor Green
New-AzResourceGroupDeployment `
		-ResourceGroupName $resourceGroupName `
		-Name $azureBlobApiConnectionName `
		-TemplateFile $azureblobTemplateFilePath `
		-TemplateParameterFile $azureblobParametersFilePath
		
$azurecustVisionApiConnectionName = "cognitiveservicescustomvision"
$outArray.Add("v_azureBlobApiConnectionName = $azurecustVisionApiConnectionName")

$azurecustVisionTemplateFilePath = "$ScriptRoot\templates\customvision-template.json"
$azurecustVisionParametersFilePath = "$ScriptRoot\templates\customvision-parameters.json"
$azurecustVisionParametersTemplate = Get-Content $azurecustVisionParametersFilePath | ConvertFrom-Json
$azurecustVisionParameters = $azurecustVisionParametersTemplate.parameters
$azurecustVisionParameters.subscription_id.value = $subscriptionId
$azurecustVisionParameters.predictive_url.value = $customVisionPredictEndpoint
$azurecustVisionParameters.customvision_key.value = $customVisionPredictSubscriptionKey
$azurecustVisionParameters.location.value = $location
$azurecustVisionParameters.connections_customvision_name.value = $azurecustVisionApiConnectionName
$azurecustVisionParametersTemplate | ConvertTo-Json | Out-File $azurecustVisionParametersFilePath

Write-Host Deploying $azurecustVisionApiConnectionName"..." -ForegroundColor Green
New-AzResourceGroupDeployment `
		-ResourceGroupName $resourceGroupName `
		-Name $azurecustVisionApiConnectionName `
		-TemplateFile $azurecustVisionTemplateFilePath `
		-TemplateParameterFile $azurecustVisionParametersFilePath


$azureformRecognizerApiConnectionName = "formrecognizer"
$outArray.Add("v_azureBlobApiConnectionName = $azureformRecognizerApiConnectionName")

$azureformRecognizerTemplateFilePath = "$ScriptRoot\templates\formrecognizer-template.json"
$azureformRecognizerParametersFilePath = "$ScriptRoot\templates\formrecognizer-parameters.json"
$azureformRecognizerParametersTemplate = Get-Content $azureformRecognizerParametersFilePath | ConvertFrom-Json
$azureformRecognizerParameters = $azureformRecognizerParametersTemplate.parameters
$azureformRecognizerParameters.subscription_id.value = $subscriptionId
$azureformRecognizerParameters.predictive_url.value = $customVisionPredictEndpoint
$azureformRecognizerParameters.formrecognizer_key.value = $customVisionPredictSubscriptionKey
$azureformRecognizerParameters.location.value = $location
$azureformRecognizerParameters.connections_formrecognizer_name.value = $azureformRecognizerApiConnectionName
$azureformRecognizerParametersTemplate | ConvertTo-Json | Out-File $azureformRecognizerParametersFilePath

Write-Host Deploying $azureformRecognizerApiConnectionName"..." -ForegroundColor Green
New-AzResourceGroupDeployment `
		-ResourceGroupName $resourceGroupName `
		-Name $azureformRecognizerApiConnectionName `
		-TemplateFile $azureformRecognizerTemplateFilePath `
		-TemplateParameterFile $azureformRecognizerParametersFilePath

$azuredocumentDbApiConnectionName = "documentdb"
$outArray.Add("v_azureBlobApiConnectionName = $azuredocumentDbApiConnectionName")

$azuredocumentDbTemplateFilePath = "$ScriptRoot\templates\cosmosdb-template.json"
$azuredocumentDbParametersFilePath = "$ScriptRoot\templates\cosmosdb-parameters.json"
$azuredocumentDbParametersTemplate = Get-Content $azuredocumentDbParametersFilePath | ConvertFrom-Json
$azuredocumentDbParameters = $azuredocumentDbParametersTemplate.parameters
$azuredocumentDbParameters.subscription_id.value = $subscriptionId
$azuredocumentDbParameters.cosmosdb_key.value = $cosmosPrimaryKey
$azuredocumentDbParameters.location.value = $location
$azuredocumentDbParameters.connections_cosmosdb_name.value = $azuredocumentDbApiConnectionName
$azuredocumentDbParameters.cosmosdb_account_name.value = $cosmosAccountName
$azuredocumentDbParametersTemplate | ConvertTo-Json | Out-File $azuredocumentDbParametersFilePath

Write-Host Deploying $azuredocumentDbApiConnectionName"..." -ForegroundColor Green
New-AzResourceGroupDeployment `
		-ResourceGroupName $resourceGroupName `
		-Name $azuredocumentDbApiConnectionName `
		-TemplateFile $azuredocumentDbTemplateFilePath `
		-TemplateParameterFile $azuredocumentDbParametersFilePath


# logic app
$logicAppName = $prefix + "lapp"
$outArray.Add("v_logicAppName = $logicAppName")

$logicAppTemplateFilePath = "$ScriptRoot\templates\fsihacklapp-template.json"
$logicAppParametersFilePath = "$ScriptRoot\templates\fsihacklapp-parameters.json"
$outArray.Add("v_logicAppTemplateFilePath = $logicAppTemplateFilePath")
$outArray.Add("v_logicAppParametersFilePath = $logicAppParametersFilePath")

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

Write-Host Deploying Logic App to Process Pdf ... -ForegroundColor Green
New-AzResourceGroupDeployment `
        -ResourceGroupName $resourceGroupName `
        -Name $logicAppName `
        -TemplateFile $logicAppTemplateFilePath `
        -TemplateParameterFile $logicAppParametersFilePath

#----------------------------------------------------------------#
#   Step 10 - Azure App and Bot Service			 #
#----------------------------------------------------------------#
$appInsightName = $prefix + "ai"
Write-Host Creating application insight account... -ForegroundColor Green
try {
	New-AzApplicationInsights `
	-ResourceGroupName $resourceGroupName `
	-Name $appInsightName `
	-Location $location `
	-Kind web
}
catch {
}

$appInsightInstrumentationKey = (Get-AzApplicationInsights -ResourceGroupName $resourceGroupName -Name $appInsightName).InstrumentationKey
$botWebApiName = $prefix + 'webapi'
$webApiSettings = @{
			serverFarmId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Web/serverFarms/$AppServicePlanName";
			alwaysOn     = $True;
		}
$currentUiWebApi = Get-AzResource `
	-ResourceGroupName $resourceGroupName `
	-ResourceName $botWebApiName 
if ( $currentUiWebApi.Name -eq $null )
{
	try {
		 New-AzResource `
		-ResourceGroupName $resourceGroupName `
		-Location $location `
		-ResourceName $botWebApiName `
		-ResourceType "microsoft.web/sites" `
		-Kind "app" `
		-Properties $webApiSettings `
		-Force
	}
	catch {
	}
}
$webAppSettings = @{
	APPINSIGHTS_INSTRUMENTATIONKEY = $appInsightInstrumentationKey;
}
	
# Configure Function App
Write-Host Configuring $botWebApiName"..." -ForegroundColor Green
Set-AzWebApp `
	-Name $botWebApiName `
	-ResourceGroupName $resourceGroupName `
	-AppSettings $webAppSettings 
		
$filePathBotApi = "$ScriptRoot\apps\fsihackbotapi.zip"
$outArray.Add("v_filePathBotApi = $filePathBotApi")

Write-Host Publishing $botWebApiName"..." -ForegroundColor Green

try {
	Publish-AzWebapp -ResourceGroupName $resourceGroupName -Name $botWebApiName -ArchivePath $filePathBotApi -Force
	}
catch {
	}

$appDisplayName = $prefix + "appId"
#a16e0d41-1743-4d9f-9c12-ae34ee7d6281
#cvJ7Q~o-46FnJynOdqiTDWzaf8WchbO-nERb_
#tiiogcmu30xqmo0a4yp8r2cqdzs5r4vj051ys4ed
# curl -k -X POST https://login.microsoftonline.com/botframework.com/oauth2/v2.0/token -d "grant_type=client_credentials&client_id=a16e0d41-1743-4d9f-9c12-ae34ee7d6281&client_secret=cvJ7Q~o-46FnJynOdqiTDWzaf8WchbO-nERb_&scope=https%3A%2F%2Fapi.botframework.com%2F.default"

$newApp = az ad app create --display-name $appDisplayName --available-to-other-tenants $true
$newAppJson = $newApp | ConvertFrom-Json
$appId = $newAppJson.appId
$startDate = Get-Date
$endDate = $startDate.AddYears(1)
$appPassword = az ad app credential reset --id $appId | ConvertFrom-Json
$clientPassword = $appPassword.password
$botName = $prefix + "bot"
$endPointName = "https://" + $botWebApiName + "azurewebsites.net/api/messages" 

$botTemplateFilePath = "$ScriptRoot\templates\azurebot-template.json"
$botParametersFilePath = "$ScriptRoot\templates\azurebot-parameters.json"
$botParametersTemplate = Get-Content $botParametersFilePath | ConvertFrom-Json
$botParameters = $botParametersTemplate.parameters
$botParameters.botservice_endpoint.value = $endPointName
$botParameters.botservice_name.value = $botName
$botParameters.msaappId.value = $appId
$botParametersTemplate | ConvertTo-Json | Out-File $botParametersFilePath

Write-Host Deploying Bot service ... -ForegroundColor Green
try {
	New-AzResourceGroupDeployment `
        -ResourceGroupName $resourceGroupName `
        -Name $botName `
        -TemplateFile $botTemplateFilePath `
        -TemplateParameterFile $botParametersFilePath		
}
catch {
}

#New-AzBotService -ResourceGroupName  $resourceGroupName -Name $botName -ApplicationId $appId -Location $location -Sku S1 -Description "Fsi Hack Bot" -Endpoint $endPointName -Registration


Write-Host Deployment complete. -ForegroundColor Green `n
