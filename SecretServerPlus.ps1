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

