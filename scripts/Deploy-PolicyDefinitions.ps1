<#
  .SYNOPSIS
    Deploy Azure Policy definitions in bulk.
  .DESCRIPTION
    This script deploys Azure Policy definitions in bulk. You can deploy one or more policy definitions by specifying the file paths, or all policy definitions in a folder by specifying a folder path.
  .PARAMETER DefinitionFile
    Path to the Policy Definition file. Supports multiple paths using array.
  .PARAMETER FolderPath
    Path to a folder that contains one or more policy definition files.
  .PARAMETER Recursive
    Use this switch together with -FolderPath to deploy policy definitions in the folder and its sub folders (recursive).
  .PARAMETER SubscriptionId
    When deploying policy definitions to a subscription, specify the subscription Id.
  .PARAMETER ManagementGroupName
    When deploying policy definitions to a management group, specify the management group name (not the display name).
  .PARAMETER Silent
    Use this switch to use the surpress login prompt. The script will use the current Azure Context (logon session) and it will fail if currently not logged on. Use this switch when using the script in CI/CD pipelines.
  .EXAMPLE
    Deploy-PolicyDefinition.ps1 -DefinitionFile C:\Temp\azurepolicy.json -SubscriptionId cd45c044-18c4-4abe-a908-1e0b79f45003
    Deploy a single policy definition to a subscription (interactive mode)
  .EXAMPLE
    Deploy-PolicyDefinition.ps1 -FolderPath C:\Temp -Recursive -ManagementGroupName myMG -Silent
    Deploy all policy definitions in a folder and its sub folders to a management group (Silent mode, i.e. in a CI/CD pipeline)
#>

#Requires -Modules 'Az.Resources'

<#
=======================================================================================
AUTHOR:  Michael Hatcher
DATE:    02/24/2021
Version: 0.4
Comment: Bulk deploy Azure policy definitions to a management group or a subscription
Note:    Used https://github.com/tyconsulting/azurepolicy as basis
=======================================================================================
#>

[CmdLetBinding()]
Param (
  [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'DeployFilesToSub', HelpMessage = 'Specify the file paths for the policy definition files.')]
  [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'DeployFilesToMG', HelpMessage = 'Specify the file paths for the policy definition files.')]
  [ValidateScript( { Test-Path $_ })][String[]]$DefinitionFile,

  [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'DeployDirToSub', HelpMessage = 'Specify the directory path that contains the policy definition files.')]
  [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'DeployDirToMG', HelpMessage = 'Specify the directory path that contains the policy definition files.')]
  [ValidateScript( { Test-Path $_ -PathType 'Container' })][String]$FolderPath,

  [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'DeployDirToSub', HelpMessage = 'Get policy definition files from the $FolderPath and its subfolders.')]
  [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'DeployDirToMG', HelpMessage = 'Get policy definition files from the $FolderPath and its subfolders.')]
  [Switch]$Recursive,

  [Parameter(Mandatory = $true, ParameterSetName = 'DeployFilesToSub')]
  [Parameter(Mandatory = $true, ParameterSetName = 'DeployDirToSub')]
  [ValidateScript( { try { [guid]::parse($_) } catch { $false } })][String]$SubscriptionId,

  [Parameter(Mandatory = $true, ParameterSetName = 'DeployFilesToMG')]
  [Parameter(Mandatory = $true, ParameterSetName = 'DeployDirToMG')]
  [ValidateNotNullOrEmpty()][String]$ManagementGroupName,

  [Parameter(Mandatory = $false, ParameterSetName = 'DeployDirToSub', HelpMessage = 'Silent mode. When used, no interative prompt for sign in')]
  [Parameter(Mandatory = $false, ParameterSetName = 'DeployDirToMG', HelpMessage = 'Silent mode. When used, no interative prompt for sign in')]
  [Parameter(Mandatory = $false, ParameterSetName = 'DeployFilesToSub', HelpMessage = 'Silent mode. When used, no interative prompt for sign in')]
  [Parameter(Mandatory = $false, ParameterSetName = 'DeployFilesToMG', HelpMessage = 'Silent mode. When used, no interative prompt for sign in')]
  [Switch]$Silent
)

#region functions
Function ProcessAzureSignIn {
  $null = Connect-AzAccount
  $Context = Get-AzContext -ErrorAction Stop
  $Script:CurrentTenantId = $Context.Tenant.Id
  $Script:CurrentSubId = $Context.Subscription.Id
  $Script:CurrentSubName = $Context.Subscription.Name
}

Function DeployPolicyDefinition {
  [CmdLetBinding()]
  Param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'DeployToSub')]
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'DeployToMG')]
    [object]$Definition,
    [Parameter(Mandatory = $true, ParameterSetName = 'DeployToSub')][String]$SubscriptionId,
    [Parameter(Mandatory = $true, ParameterSetName = 'DeployToMG')][String]$ManagementGroupName
  )

  #Extract from policy definition
  $PolicyName = $Definition.name
  $PolicyDisplayName = $Definition.properties.displayName
  $PolicyDescription = $Definition.properties.description
  $PolicyParameters = $Definition.properties.parameters | ConvertTo-Json
  $PolicyRule = $Definition.properties.policyRule | ConvertTo-Json -Depth 15
  $PolicyMetaData = $Definition.properties.metadata | ConvertTo-Json
  $DeployParams = @{
    Name        = $PolicyName
    DisplayName = $PolicyDisplayName
    Description = $PolicyDescription
    Parameter   = $PolicyParameters
    Policy      = $PolicyRule
    Metadata    = $PolicyMetaData
  }

  Write-Verbose "  - 'DeployPolicyDefinition' function parameter set name: '$($PSCmdlet.ParameterSetName)'"
  If ($PSCmdlet.ParameterSetName -eq 'DeployToSub') {
    Write-Verbose "  - Adding SubscriptionId to the input parameters for New-AzPolicyDefinition cmdlet"
    $DeployParams.Add('SubscriptionId', $SubscriptionId)
  }
  else {
    Write-Verbose "  - Adding ManagementGroupName to the input parameters for New-AzPolicyDefinition cmdlet"
    $DeployParams.Add('ManagementGroupName', $ManagementGroupName)
  }
  $DeployResult = New-AzPolicyDefinition @DeployParams
  $DeployResult
}
#endregion

#region main
#ensure signed in to Azure
if ($Silent) {
  Write-Verbose "Running script in Silent mode."
}
Try {
  $Context = Get-AzContext -ErrorAction SilentlyContinue
  $CurrentTenantId = $Context.Tenant.Id
  $CurrentSubId = $Context.Subscription.Id
  $CurrentSubName = $Context.Subscription.Name
  if ($null -ne $Context) {
    Write-Output "You are currently signed to to tenant '$CurrentTenantId', subscription '$CurrentSubName'  using account '$($Context.Account.Id).'"
    if (!$Silent) {
      Write-Output '', "Press any key to continue using current sign-in session or Esc to login using another user account."
      $KeyPress = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
      If ($KeyPress.virtualKeyCode -eq 27) {
        #sign out first
        Disconnect-AzAccount -AzureContext $Context
        #sign in
        ProcessAzureSignIn
      }
    }
  }
  else {
    if (!$Silent) {
      Write-Output '', "You are currently not signed in to Azure. Please sign in from the pop-up window."
      ProcessAzureSignIn
    }
    else {
      Throw "You are not signed in to Azure!"
    }

  }
}
Catch {
  if (!$Silent) {
    #sign in
    ProcessAzureSignIn
  }
  else {
    Throw "You are not signed in to Azure!"
  }
}

#Read all definitions
If ($PSCmdlet.ParameterSetName -eq 'DeployDirToMG' -or $PSCmdlet.ParameterSetName -eq 'DeployDirToSub') {
  If ($Recursive) {
    Write-Verbose "A folder path with -Recursive switch is used. Retrieving all JSON files in the folder and its sub folders."
    $DefinitionFile = (Get-ChildItem -Path $FolderPath -File -Filter '*.json' -Recursive).FullName
    Write-Verbose "Number of JSON files located in folder '$FolderPath': $($DefinitionFile.count)."
  }
  else {
    Write-Verbose "A folder path is used. Retrieving all JSON files in the folder."
    $DefinitionFile = (Get-ChildItem -Path $FolderPath -File -Filter '*.json').FullName
    Write-Verbose "Number of JSON files located in folder '$FolderPath': $($DefinitionFile.count)."
  }

}
$Definitions = @()
Foreach ($File in $DefinitionFile) {
  Write-Verbose "Processing '$File'..."
  $ObjDef = Get-Content -Path $File | ConvertFrom-Json
  If ($ObjDef.properties.policyDefinitions) {
    Write-Verbose "'$File' is a policy initiative definition. policy initiatives are not supported by this script."
  }
  elseif ($ObjDef.properties.policyRule) {
    Write-Verbose "'$File' contains a policy definition. It will be deployed."
    $Definitions += $ObjDef
  }
  else {
    Write-Warning "Unable to parse '$File'. It is not a policy definition file. Content unrecognised."
  }
}

#Deploy definitions
$ArrDeployResults = @()
Foreach ($ObjDef in $Definitions) {
  $Params = @{
    Definition = $ObjDef
  }
  If ($PSCmdlet.ParameterSetName -eq 'DeployDirToSub' -or $PSCmdlet.ParameterSetName -eq 'DeployFilesToSub') {
    Write-Verbose "Deploying policy '$($ObjDef.name)' to subscription '$SubscriptionId'"
    $Params.Add('SubscriptionId', $SubscriptionId)
  }
  else {
    Write-Verbose "Deploying policy '$($ObjDef.name)' to management group '$ManagementGroupName'"
    $Params.Add('ManagementGroupName', $ManagementGroupName)
  }
  $DeployResult = DeployPolicyDefinition @Params
  $ArrDeployResults += $DeployResult
}

$ArrDeployResults
#endregion
