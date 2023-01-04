#######################################
#region ### MAJOR FUNCTIONS ###########
#######################################

###########
#region ### global:Connect-SecretServerInstance # TEMPLATE
###########
function global:Connect-SecretServerInstance
{
	param
	(
		[Parameter(Mandatory = $false, Position = 0, HelpMessage = "Specify the URL to use for the connection (e.g. oceanlab.secretservercloud.com).")]
		[System.String]$Url,

		[Parameter(Mandatory = $true, HelpMessage = "Specify the User login to use for the connection (e.g. CloudAdmin@oceanlab.secretservercloud.com).")]
		[System.String]$User
	)

	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

	# Debug preference
	if ($PSCmdlet.MyInvocation.BoundParameters["Debug"].IsPresent)
	{
		# Debug continue without waiting for confirmation
		$DebugPreference = "Continue"
	}
	else 
	{
		# Debug message are turned off
		$DebugPreference = "SilentlyContinue"
	}

	# Check if URL provided has "https://" in front, if so, remove it.
	if ($Url.ToLower().Substring(0,8) -eq "https://")
	{
		$Url = $Url.Substring(8)
	}

	$Uri = ("https://{0}/oauth2/token" -f $Url)
	Write-Host ("Connecting to Delinea Secret Server Instance (https://{0}) as {1}`n" -f $Url, $User)

	# Debug informations
	Write-Debug ("Uri= {0}" -f $Uri)
	Write-Debug ("User= {0}" -f $User)

	$SecureString = Read-Host -Prompt "Password" -AsSecureString

	$Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString))

	# setting the body
	$Body = @{}
	$Body.username = $User
	$Body.password = $Password
	$Body.grant_type = "password"

	# setting the header
	$Header = @{}
	$Header."Content-Type" = "application/x-www-form-urlencoded"

	Try
	{
		$InitialResponse = Invoke-WebRequest -UseBasicParsing -Method POST -SessionVariable SSSession -Uri $Uri -Body $Body -Headers $Header
	}
	Catch
	{
		$LastError = [SSAPIException]::new("A SecretServerAPI error has occured. Check `$LastError for more information")
        $LastError.APICall = $APICall
        $LastError.Payload = $Body
        $LastError.Response = $InitialResponse
        $LastError.ErrorMessage = $_.Exception.Message
        $global:LastError = $LastError
        Throw $_.Exception
	}

	# if the initial response was successful
	if ($InitialResponse.StatusCode -eq 200)
	{
		$accesstoken = $InitialResponse.Content | ConvertFrom-Json | Select-Object -ExpandProperty access_token

		$Connection = New-Object -TypeName PSCustomObject

		$Connection | Add-Member -MemberType NoteProperty -Name PodFqdn -Value $Url
		$Connection | Add-Member -MemberType NoteProperty -Name User -Value $User
		$Connection | Add-Member -MemberType NoteProperty -Name SessionStartTime -Value $InitialResponse.Headers.Date
		#$Connection | Add-Member -MemberType NoteProperty -Name Response -Value $InitialResponse

		# Set Connection as global
		$global:SecretServerConnection = $Connection

		# setting the bearer token header
		$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
		$headers.Add("Authorization","Bearer $accesstoken")

		# setting the splat
		$global:SecretServerSessionInformation = @{ Headers = $headers; ContentType = "application/json" }

		return ($Connection | Select-Object User,PodFqdn | Format-List)
	}# if ($InitialResponse.StatusCode -eq 200)
	else
	{
		Write-Host ("Connection failed.")
		return $InitialResponse
	}

	#return $InitialResponse
}# function global:Connect-SecretServerInstance
#endregion
###########

###########
#region ### global:TEMPLATE # TEMPLATE
###########
function global:Invoke-SecretServerAPI
{
	param
    (
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Specify the API call to make.")]
        [System.String]$APICall,

		[Parameter(Position = 1, Mandatory = $false, HelpMessage = "Specify Invoke Method.")]
        [System.String]$Method = "GET",

        [Parameter(Position = 2, Mandatory = $false, HelpMessage = "Specify the JSON Body payload.")]
        [System.String]$Body

    )

	# setting the url based on our PlatformConnection information
    $uri = ("https://{0}/{1}" -f $global:SecretServerConnection.PodFqdn, $APICall)

	# Try
    Try
    {
        Write-Debug ("Uri=[{0}]" -f $uri)
        Write-Debug ("Body=[{0}]" -f $Body)

        # making the call using our a Splat version of our connection
        #$Response = Invoke-RestMethod -Method Get -Uri $uri -Body $Body @global:SecretServerSessionInformation
		# if -Body was used, include that
		if ($PSBoundParameters.ContainsKey('Body'))
		{
			$Response = Invoke-RestMethod -Uri $uri -Method $Method -Body $Body @global:SecretServerSessionInformation
		}
		else # don't include the Body parameter
		{
			$Response = Invoke-RestMethod -Uri $uri -Method $Method @global:SecretServerSessionInformation
		}
		
		
		return $Response
		
    }# Try
    Catch
    {
        $LastError = [SSAPIException]::new("A SecretServerAPI error has occured. Check `$LastError for more information")
        $LastError.APICall = $APICall
        $LastError.Payload = $Body
        $LastError.Response = $Response
        $LastError.ErrorMessage = $_.Exception.Message
        $global:LastError = $LastError
        Throw $_.Exception
    }
}# function global:Invoke-TEMPLATE
#endregion
###########

###########
#region ### global:New-SecretServerFolder # Creates a new Secret Server Folder
###########
function global:New-SecretServerFolder
{
	param
    (
		[Parameter(Position = 0, Mandatory = $true, HelpMessage = "Specify parent Folder for this new Folder. Default is the Root Folder.")]
        [System.String]$Name,

        [Parameter(Position = 0, Mandatory = $false, HelpMessage = "Specify parent Folder for this new Folder. Default is the Root Folder.")]
        [System.String]$ParentFolder = "Root"
    )# param

	if ($ParentFolder -eq "Root")
	{
		$parentFolderId = -1
		$inheritPermissions = "false"
		$inheritSecretPolicy = "false"
	}
	else
	{
		# get the folders
		$Folders = Invoke-SecretServerAPI -API api/v1/folders

		# if there is a folder that name matches the ParentFolder parameter
		if ($folder = $Folders.records | Where-Object {$_.folderName -eq $ParentFolder})
		{
			# set the parentFolderId to this folder's ID
			$parentFolderId = $folder.id
			$inheritPermissions = "true"
			$inheritSecretPolicy = "true"
		}
		else
		{
			Write-Host ("Parent Folder [{0}] not found." -f $ParentFolder)
			return $false
		}
	}# else

	# preparing the JSON body
	$JSONBody = @{}
	$JSONBody.folderName = $Name
	$JSONBody.folderTypeId = 1
	$JSONBody.inheritPermissions = $inheritPermissions
	$JSONBody.inheritSecretPolicy = $inheritSecretPolicy
	$JSONBody.parentFolderId = $parentFolderId
	$JSONBody = $JSONBody | ConvertTo-Json

	# create the folder
	Invoke-SecretServerAPI -APICall api/v1/folders/ -Method POST -Body $JSONBody
}# function global:New-SecretServerFolder
#endregion
###########

###########
#region ### global:New-SecretServerSecret # Could be better but it works
###########
function global:New-SecretServerSecret
{
	param
    (
		[Parameter(Position = 0, Mandatory = $true, HelpMessage = "Specify the name of this Secret.")]
        [System.String]$Name,

        [Parameter(Position = 1, Mandatory = $false, HelpMessage = "Specify the parent Folder Id.")]
        [System.String]$FolderId,

		[Parameter(Position = 2, Mandatory = $true, HelpMessage = "Specify Secret Template Id.")]
        [System.String]$SecretTemplateId,

		[Parameter(Position = 3, Mandatory = $true, HelpMessage = "Specify the Site.")]
        [System.String]$Site,

		[Parameter(Position = 4, Mandatory = $true, HelpMessage = "Specify the slugs.")]
        [PSCustomObject[]]$Slugs
    )# param

	# initial payload set
	$data = @{}

	# adding fields
	$data.autoChangePassword = ""
	$data.enableInheritSecretPolicy = $true
	$data.folderId = $FolderId
	$data.generateSshKeys = $false
	$data.name = $Name
	$data.secretPolicy = ""
	$data.site = $Site
	$data.templateId = $SecretTemplateId

	# new ArrayList for the slugs
	$fields = New-Object System.Collections.ArrayList

	# adding the slugs and fields
	$fields.AddRange(@($Slugs)) | Out-Null
	$data.fields = $fields

	# new hashtable for the parent 
	$JSONBody = @{}
	$JSONBody.data = $data

	# creating the secret
	Invoke-SecretServerAPI -APICall internals/secret-detail -Method POST -Body ($JSONBody | ConvertTo-Json -Depth 5)
}# function global:New-SecretServerSecret
#endregion
###########

###########
#region ### global:TEMPLATE # TEMPLATE
###########
function global:Get-SecretServerFolderId
{
	param
    (
		[Parameter(Position = 0, Mandatory = $true, HelpMessage = "Specify the name of the Folder to get the FolderId.")]
        [System.String]$Name
    )# param

	# get the folder count
	$FoldersforCount = Invoke-SecretServerAPI -APICall api/v1/folders

	# getting all the folders
	$Folders = Invoke-SecretServerAPI -APICall ("api/v1/folders?take={0}" -f $FoldersforCount.total)


	return $Folders.records | Where-Object {$_.folderName -eq $Name} | Select-Object -ExpandProperty id
}# function global:Get-SecretServerFolderId
#endregion
###########

###########
#region ### global:Get-SecretServerSecretTemplate # TEMPLATE
###########
function global:Get-SecretServerSecretTemplate
{
	param
    (
		[Parameter(Position = 0, Mandatory = $false, HelpMessage = "Specify the name of the Secret Template.")]
        [System.String]$Name
    )# param

	# getting the template count
	$TemplatesCount = Invoke-SecretServerAPI -APICall api/v1/secret-templates

	# getting all the templates
	$Templates = Invoke-SecretServerAPI -APICall ("api/v1/secret-templates?take={0}" -f $TemplatesCount.total)

	if ($PSBoundParameters.ContainsKey('Name'))
	{
		return $Templates.records | Where-Object {$_.name -eq $Name}
	}
	else
	{
		return $Templates.records
	}
}# function global:Get-SecretServerSecretTemplate
#endregion
###########

###########
#region ### global:Get-SecretServerSecretTemplateId # TEMPLATE
###########
function global:Get-SecretServerSecretTemplateId
{
	param
    (
		[Parameter(Position = 0, Mandatory = $false, HelpMessage = "Specify the name of the Secret Template.")]
        [System.String]$Name
    )# param

	# getting the template count
	$TemplatesCount = Invoke-SecretServerAPI -APICall api/v1/secret-templates

	# getting all the templates
	$Templates = Invoke-SecretServerAPI -APICall ("api/v1/secret-templates?take={0}" -f $TemplatesCount.total)

	return $Templates.records | Where-Object {$_.name -eq $Name} | Select-Object -ExpandProperty id
}# function global:Get-SecretServerSecretTemplateId
#endregion
###########

###########
#region ### global:TEMPLATE # TEMPLATE
###########
#function global:Invoke-TEMPLATE
#{
#}# function global:Invoke-TEMPLATE
#endregion
###########

#######################################
#endregion ############################
#########

#######################################
#region ### SUB FUNCTIONS #############
#######################################

###########
#region ### global:New-Slug # TEMPLATE
###########
function global:New-Slug
{
	param
    (
		[Parameter(Position = 0, Mandatory = $true, HelpMessage = "Specify the name of the property.")]
        [System.String]$Name, 

		[Parameter(Position = 1, Mandatory = $true, HelpMessage = "Specify the value of the property.")]
        [System.String]$Value
    )# param

	$slug = @{}
	$slug.slug = $Name
	$slug.value = $Value

	return $slug
}# function global:New-Slug
#endregion
###########

###########
###########
#region ### global:TEMPLATE # TEMPLATE
###########
#function global:Invoke-TEMPLATE
#{
#}# function global:Invoke-TEMPLATE
#endregion
###########

#######################################
#endregion ############################
#######################################

#######################################
#region ### CLASSES ###################
#######################################

# class to hold a custom SSError
class SSAPIException : System.Exception
{
    [System.String]$APICall
    [System.String]$Payload
    [System.String]$ErrorMessage
    [PSCustomObject]$Response

    SSAPIException([System.String]$message) : base ($message) {}

    SSAPIException() {}
}# class SSAPIException : System.Exception

#######################################
#endregion ############################
#######################################

