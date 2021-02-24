<#
  .SYNOPSIS
    Deploy Azure Policy Initiative (policy set) definition.
  .DESCRIPTION
    This script deploys Azure Policy Initiative (policy set) definition.
  .PARAMETER DefinitionFile
    Path to the Policy Initiative Definition file.
  .PARAMETER PolicyLocations
    When the policy initiative contains custom policies, instead of hardcoding the policy definition resource Id, use a string to represent the location (resource Id to a subscription or a management group where the policy definition resides.) and replace this string with the value specified in this parameter. See Example for detailed usage
  .PARAMETER SubscriptionId
    When deploying the policy initiative definition to a subscription, specify the subscription Id.
  .PARAMETER ManagementGroupName
    When deploying the policy initiative definition to a management group, specify the management group name (not the display name).
  .PARAMETER Silent
    Use this switch to use the surpress login prompt. The script will use the current Azure context (logon session) and it will fail if currently not logged on. Use this switch when using the script in CI/CD pipelines.
  .EXAMPLE
    Deploy-PolicySetDefinition.ps1 -DefinitionFile C:\Temp\azurepolicyset.json -SubscriptionId cd45c044-18c4-4abe-a908-1e0b79f45003
    Deploy a policy initiative definition to a subscription (interactive mode)
  .EXAMPLE
    Deploy-PolicySetDefinition.ps1 -DefinitionFile C:\Temp\azurepolicyset.json -ManagementGroupName myMG -Silent
    Deploy a policy initiative definition to a management group (silent mode, i.e. in a CI/CD pipeline)
  .EXAMPLE
    Deploy-PolicySetDefinition.ps1 -DefinitionFile C:\Temp\azurepolicyset.json -ManagementGroupName myMG -PolicyLocations @{policyLocationResourceId1 = '/providers/Microsoft.Management/managementGroups/MyMG'}
    Deploy a policy initiative definition to a management group and replace the policy location from the definition file as shown below:
    {
    "name": "storage-account-network-restriction-policySetDef",
    "properties": {
        "displayName": "My Policy Initiative",
        "description": "This is my test initiative",
        "metadata": {
            "category": "General"
        },
        "parameters": {},
        "policyDefinitions": [
            {
                "policyDefinitionId": "{policyLocationResourceId1}/providers/Microsoft.Authorization/policyDefinitions/custom1-policyDef"
            },
            {
                "policyDefinitionId": "{policyLocationResourceId1}/providers/Microsoft.Authorization/policyDefinitions/custom2-policyDef"
            }
        ]
    }
}
#>

#Requires -Modules 'Az.Resources'

<#
======================================================================================================================================
AUTHOR:  Michael Hatcher
DATE:    02/24/2021
Version: 0.2
Comment: Alternative method to deploy Azure policy set (Initiative) definitions to a management group or a subscription
Note:    Used https://github.com/tyconsulting/azurepolicy as basis
======================================================================================================================================
#>

[CmdLetBinding()]
Param (
  [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'DeployToSub', HelpMessage = 'Specify the file path for the policy initiative definition file.')]
  [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'DeployToMG', HelpMessage = 'Specify the file path for the policy initiative definition file.')]
  [ValidateScript( { Test-Path $_ })][String]$DefinitionFile,

  [Parameter(Mandatory = $false, ValueFromPipeline = $true, ParameterSetName = 'DeployToSub', HelpMessage = 'Specify hashtable that contains policy definition locations that the script will find and replace from the policy set definition.')]
  [Parameter(Mandatory = $false, ValueFromPipeline = $true, ParameterSetName = 'DeployToMG', HelpMessage = 'Specify hashtable that contains policy definition locations that the script will find and replace from the policy set definition.')]
  [hashtable]$PolicyLocations,

  [Parameter(Mandatory = $true, ParameterSetName = 'DeployToSub')]
  [ValidateScript( { try { [guid]::parse($_) } catch { $false } })][String]$SubscriptionId,

  [Parameter(Mandatory = $true, ParameterSetName = 'DeployToMG')]
  [ValidateNotNullOrEmpty()][String]$ManagementGroupName,

  [Parameter(Mandatory = $false, ParameterSetName = 'DeployToSub', HelpMessage = 'Silent mode. When used, no interative prompt for sign in')]
  [Parameter(Mandatory = $false, ParameterSetName = 'DeployToMG', HelpMessage = 'Silent mode. When used, no interative prompt for sign in')]
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

Function DeployPolicySetDefinition {
  [CmdLetBinding()]
  Param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'DeployToSub')]
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'DeployToMG')]
    [object]$Definition,
    [Parameter(Mandatory = $true, ParameterSetName = 'DeployToSub')][String]$SubscriptionId,
    [Parameter(Mandatory = $true, ParameterSetName = 'DeployToMG')][String]$ManagementGroupName
  )

  #Extract from policy definition
  $PolicySetName = $Definition.name
  $PolicySetDisplayName = $Definition.properties.displayName
  $PolicySetDescription = $Definition.properties.description
  $PolicySetParameters = ConvertTo-Json -InputObject $Definition.properties.parameters -Depth 15
  $PolicySetDefinition = ConvertTo-Json -InputObject $Definition.properties.policyDefinitions -Depth 15
  $PolicySetMetaData = ConvertTo-Json -InputObject $Definition.properties.metadata -Depth 15

  If ($PSCmdlet.ParameterSetName -eq 'DeployToSub') {
    Write-Verbose "Deploying Policy Initiative '$PolicySetName' to subscription '$SubscriptionId'"
  }
  else {
    Write-Verbose "Deploying Policy Initiative '$PolicySetName' to management group '$ManagementGroupName'"
  }

  $DeployParams = @{
    Name             = $PolicySetName
    DisplayName      = $PolicySetDisplayName
    Description      = $PolicySetDescription
    Parameter        = $PolicySetParameters
    PolicyDefinition = $PolicySetDefinition
    Metadata         = $PolicySetMetaData
  }

  Write-Verbose "  - 'DeployPolicySetDefinition' function parameter set name: '$($PSCmdlet.ParameterSetName)'"
  If ($PSCmdlet.ParameterSetName -eq 'DeployToSub') {
    Write-Verbose "  - Adding SubscriptionId to the input parameters for New-AzPolicySetDefinition cmdlet"
    $DeployParams.Add('SubscriptionId', $SubscriptionId)
  }
  else {
    Write-Verbose "  - Adding ManagementGroupName to the input parameters for New-AzPolicySetDefinition cmdlet"
    $DeployParams.Add('ManagementGroupName', $ManagementGroupName)
  }
  Write-Verbose "Initiative Definition:"
  Write-Verbose $PolicySetDefinition
  $DeployResult = New-AzPolicySetDefinition @DeployParams
  $DeployResult
}
#endregion

#region main
#ensure signed in to Azure
if ($Silent) {
  Write-Verbose "Running script in silent mode."
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

#Read initiative definition
Write-Verbose "Processing '$DefinitionFile'..."
$DefFileContent = Get-Content -Path $DefinitionFile -Raw

#replace policy definition resource Ids
If ($PSBoundParameters.ContainsKey('PolicyLocations')) {
  Write-Verbose "Replacing policy definition locations in the initiative definition file."
  Foreach ($Key in $PolicyLocations.Keys) {
    $DefFileContent = $DefFileContent.Replace("{$Key}", $PolicyLocations.$Key)
  }
}
$ObjDef = ConvertFrom-Json -InputObject $DefFileContent

#Validate definition content
If ($ObjDef.properties.policyDefinitions) {
  Write-Verbose "'$DefinitionFile' is a policy initiative definition. It will be deployed."
  $BProceed = $true
}
elseif ($ObjDef.properties.policyRule) {
  Write-Warning "'$DefinitionFile' contains a policy definition. policy definitions are not supported by this script. please use deploy-policyDef.ps1 to deploy policy definitions."
  $BProceed = $false
}
else {
  Write-Error "Unable to parse '$DefinitionFile'. It is not a policy or initiative definition file. Content unrecognised."
  $BProceed = $false
}

#Deploy definitions
if ($BProceed -eq $true) {
  $Params = @{
    Definition = $ObjDef
  }
  If ($PSCmdlet.ParameterSetName -eq 'deployToSub') {
    $Params.Add('subscriptionId', $SubscriptionId)
  }
  else {
    $Params.Add('managementGroupName', $ManagementGroupName)
  }
  $DeployResult = DeployPolicySetDefinition @Params
}
$DeployResult
#endregion