using namespace System.IO
using namespace System.Text

Set-StrictMode -Version 'Latest'
#Requires -Version 5.0

$PSDefaultParameterValues.Clear()

function Get-BuildEnvironment {
<#
  .SYNOPSIS
  Gathers the appropriate build environment variables in Azure DevOps
  required for the download process and returns a custom object containing
  the values
#>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    process {
        [PSCustomObject](@{
                OrganizationUri = $env:SYSTEM_TEAMFOUNDATIONSERVERURI
                Project         = $env:SYSTEM_TEAMPROJECT
                AccessToken     = $env:SYSTEM_ACCESSTOKEN
                BuildUri        = $env:BUILD_BUILDURI
                CommonTestResultsFolder = $env:COMMON_TESTRESULTSDIRECTORY
                TempTestResultsFolder = "$env:AGENT_TEMPDIRECTORY/TestResults"
                ProjectUri      = "$($env:SYSTEM_TEAMFOUNDATIONSERVERURI)/$($env:SYSTEM_TEAMPROJECT)"
            })
    }
}

function Get-AuthorizationHeader {
<#
  .SYNOPSIS
  Creates the HTTP Authorization Header.
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory)]
        [string]$Token
    )

    process {
        "Basic " + [Convert]::ToBase64String([Encoding]::ASCII.GetBytes(("{0}:{1}" -f '', $Token)))
    }
}

function Get-TrxAttachmentList {
<#
  .SYNOPSIS
  Gets the list of coverage attachments from a TRX file.
#>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string] $FilePath
    )

    process {
        $xml = [xml] (Get-Content $FilePath -ErrorAction Stop)
        $ns = New-Object Xml.XmlNamespaceManager $xml.NameTable
        $ns.AddNamespace( "ns", 'http://microsoft.com/schemas/VisualStudio/TeamTest/2010')
        $nodes = $xml.SelectNodes('//ns:UriAttachments/ns:UriAttachment/ns:A/@href', $ns) | Select-Object -ExpandProperty '#text'
        $nodes
    }
}

function Get-TestRunList {
<#
  .SYNOPSIS
  Invokes an Azure DevOps REST call to retrieve the list of test runs associated with the build

  .PARAMETER BuildUri
  The URI of the build associated with the tests

  .PARAMETER BaseUri
  The base URI containing the organization name and project name, such
  as https://dev.azure.com/myOrg/myProject.

  .PARAMETER AccessToken
  A PAT token or build access token providing authorization for the request
#>
    [CmdletBinding()]
    [OutputType([psobject[]])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string] $BuildUri,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string] $BaseUri,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string] $AccessToken
    )

    process {
        $AuthHeader = Get-AuthorizationHeader $AccessToken

        $params = @{
            Uri     = "$BaseUri/_apis/test/runs?api-version=5.0&buildUri=$BuildUri"
            Headers = @{
                Authorization = $AuthHeader
                Accept        = 'application/json'
            }
            Method  = 'Get'
        }

        $content = (Invoke-WebRequestWithRetry -Parameters $params).Content
        Write-Verbose "Received $content"
        ($content | ConvertFrom-Json).value
    }
}

function Get-TestAttachmentList {
<#
  .SYNOPSIS
  Invokes an Azure DevOps REST call to retrieve the test run details for a specific test

  .PARAMETER TestUri
  The URI for retrieving the test details

  .PARAMETER AccessToken
  A PAT token or build access token providing authorization for the request
#>
    [CmdletBinding()]
    [OutputType([psobject[]])]
    param(
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory)]
        [string] $TestUri,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string] $AccessToken
    )

    process {
        $AuthHeader = Get-AuthorizationHeader $AccessToken

        $params = @{
            Uri     = "$TestUri/attachments?api-version=5.0-preview.1"
            Headers = @{
                Authorization = $AuthHeader
                Accept        = 'application/json'
            }
            Method  = 'Get'
        }

        $content = (Invoke-WebRequestWithRetry -Parameters $params).Content
        Write-Verbose "Received $content"
        [PsCustomObject[]]($content | ConvertFrom-Json).value
    }
}

function Get-TestAttachment {
<#
  .SYNOPSIS
  Invokes an Azure DevOps REST call to retrieve a specific test attachment

  .PARAMETER AttachmentUri
  The URI for retrieving the test attachment

  .PARAMETER OutputPath
  The absolute path to a folder or file where the content should be saved.

  .PARAMETER AccessToken
  A PAT token or build access token providing authorization for the request
#>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory)]
        [string] $AttachmentUri,

        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory)]
        [string] $OutputPath,

        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory)]
        [string] $AccessToken
    )

    process {
        $AuthHeader = Get-AuthorizationHeader $AccessToken

        $params = @{
            Uri     = $AttachmentUri
            Headers = @{
                Authorization = $AuthHeader
                Accept        = 'application/octet-stream'
            }
            Method  = 'Get'
            OutFile = $OutputPath
        }

        Write-Verbose "Downloading '$AttachmentUri' to '$OutputPath'"
        Invoke-WebRequestWithRetry $params
    }
}

function Join-FilePath {
<#
  .SYNOPSIS
  Combines two filesystem paths and returns the full path, with proper OS-specific
  directory separators
#>
    [CmdletBinding()]
	[OutputType([string])]
    param(
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory, Position = 0)]
        [string] $Path,

        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory, Position = 1)]
        [string] $ChildPath
    )
    process {
        $combinedPath = [Path]::Combine($Path, $ChildPath)
		[Path]::GetFullPath($combinedPath)
    }
}

function Invoke-WebRequestWithRetry {
<#
  .SYNOPSIS
  A variant of the Invoke-WebRequest method which supports automatic retries
#>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNull()]
        [hashtable] $Parameters,

        [int] $MaxRetries = 3,

        [int] $SleepTime = 1000
    )

    process {
        $isComplete = $true
        $retryCount = 0
        do {
            try {
                $result = Invoke-WebRequest @Parameters -ErrorAction Stop -UseBasicParsing
                $isComplete = $true
                $result
            }
            catch {
                Write-Verbose $_.Exception
                if ($retryCount -ge $MaxRetries) {
                    $isComplete = $true
                    Throw (New-Object InvalidOperationException("Failed after $MaxRetries retries, $_.Exception"))
                }
                else {
                    $retryCount ++
                    $isComplete = $false
                    Write-Verbose "Failed: Retry $retryCount of $MaxRetries"
                    Start-Sleep -Milliseconds $SleepTime
                }
            }
        } while (-not $isComplete)
    }
}

function Group-TestAttachmentList {
<#
  .SYNOPSIS
  Gathers the list of attachments into files which represent Test Run Summaries (TRX files)
  and all other content
#>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [ValidateNotNull()]
        [PSCustomObject[]] $Attachments
    )

    process {
        $trxFiles = New-Object System.Collections.ArrayList
        $otherFiles = New-Object System.Collections.ArrayList
        foreach ($attachment in $Attachments) {
            if ('attachmentType' -in $attachment.PSobject.Properties.name) {
                $attachmentType = ($attachment | Select-Object -ExpandProperty 'attachmentType' -First 1)
                if ('tmiTestRunSummary' -eq $attachmentType) {
                    [void]$trxFiles.Add($attachment)
                }
                else {
                    [void]$otherFiles.Add($attachment)
                }
            }
            else {
                $extension = [Path]::GetExtension($attachment.fileName)
                if ('.trx' -eq $extension) {
                    [void]$trxFiles.Add($attachment)
                }
                else {
                    [void]$otherFiles.Add($attachment)
                }
            }
        }
        [PsCustomObject]@{
            TrxContent   = $trxFiles.ToArray()
            OtherContent = $otherFiles.ToArray()
        }
    }
}

function Get-GroupedAttachmentList {
<#
  .SYNOPSIS
  Downloads the list of test attachments and groups the results of files which represent
  Test Run Summaries (TRX files) and all other content
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Uri] $TestUri,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string] $AccessToken
    )
    process {
        $attachments = Get-TestAttachmentList -TestUri $TestUri -AccessToken $AccessToken
        Group-TestAttachmentList -Attachments $attachments
    }
}

function Get-TrxContent {
<#
  .SYNOPSIS
  Downloads the TRX file and returns an array of expected child content paths.
#>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [ValidateNotNull()]
        [PsCustomObject[]] $Files,

        [Parameter(Mandatory, ValueFromPipeline, Position = 1)]
        [ValidateNotNull()]
        [string] $OutputFolder,

        [Parameter(ValueFromPipeline)]
        [string] $OutputFolderFormat = '$trxFolder/In/$folder'
    )
    process {
        $trxChildPaths = New-Object System.Collections.ArrayList
        foreach ($trxFile in $Files) {
            Write-Verbose "Downloading TRX: $($trxFile.fileName)"
            $trxFolder = [Path]::GetFileNameWithoutExtension($trxFile.fileName).Replace(' ', '_')
            $trxDirectoryName = Join-FilePath -Path $OutputFolder -ChildPath $trxFolder
            Write-Verbose "Configuring TRX folder: $trxDirectoryName"
            $trxAttachments = Get-TrxAttachmentList -FilePath (Join-FilePath -Path $OutputFolder -ChildPath $trxFile.fileName)
            Write-Verbose "Processing attachments"
            foreach ($node in $trxAttachments) {
                $normalizedNode = (Join-Path -Path '.' -ChildPath $node).Substring(2)
                $folder = [Path]::GetDirectoryName($normalizedNode)
                Write-Verbose "$node  => $folder"
                if ($OutputFolderFormat.StartsWith('/') -or $OutputFolderFormat.StartsWith('\')) {
                    $OutputFolderFormat = $OutputFolderFormat.Substring(1)
                }

                $expandedPath = $ExecutionContext.InvokeCommand.ExpandString($OutputFolderFormat)
                if ($expandedPath) {
                    $nodePath = Join-FilePath -Path $OutputFolder -ChildPath $expandedPath
                }
                else {
                    $nodePath = $OutputFolder
                }

                $nodeFileName = [Path]::GetFileName($node)
                Write-Verbose "The file '$nodeFileName' will be stored at '$nodePath'"
                $path = Join-FilePath -Path $nodePath -ChildPath $nodeFileName
                [void]$trxChildPaths.Add($path)
            }
        }

        $trxChildPaths.ToArray()
    }
}

function Group-ChildContent {
<#
  .SYNOPSIS
  Determines the proper file locations for a set of files given the list of TRX child paths,
  the content files being downloaded, and the Output Folder and returns a hash list of file
  names and their destinations.

  .PARAMETER TrxContentList
  The list of paths for expected TRX child content

  .PARAMETER FileList
  The list of files to be examined

  .PARAMETER OutputFolder
  The output destination for non-TRX children
#>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [ValidateNotNull()]
        [string[]] $TrxContentList,

        [Parameter(Mandatory, ValueFromPipeline, Position = 1)]
        [ValidateNotNull()]
        [string[]] $FileList,

        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [string] $OutputFolder
    )
    process {
        $fileHash = @{ }
        $files = $FileList | Get-Unique
        if ($null -ne $TrxContentList) {
            $childContent = $files | Where-Object { [Path]::GetExtension($_) -eq '.coverage' }
            # foreach child get the matching TRX reference
            foreach ($child in $childContent) {
                $outArr = [array]($TrxContentList | Where-Object { [Path]::GetFileName($_) -eq  $child })
                [void]$fileHash.Add($child, $outArr)
            }

            $simpleContent = $files | Where-Object { $childContent -notcontains $_ }
            $simpleContent | Foreach-Object { [void]$fileHash.Add($_,  "$OutputFolder/$_" ) }
        }
        else {
            $files | Foreach-Object { [void]$fileHash.Add($_, "$OutputFolder/$_" ) }
        }
        $fileHash
    }
}

function Copy-TestResultToCommon {
<#
 .SYNOPSIS
 Retrieves test results for SonarQube from the current Azure DevOps build and places them in the
 Common Test Results folder ($Common.TestResultsDirectory)

 .DESCRIPTION
 Retrieves the test attachments from a build and places them in appropriate locations
 for SonarQube. This method expects the Azure DevOps environment variables to be set
 in order to automatically determine the location and build identity. This method calls
 Copy-TestResult using the appropriate Azure DevOps environment variables.

 .EXAMPLE
 Copy-TestResultToCommon
#>
    [CmdletBinding()]
    param()
    process {
        $buildEnv = Get-BuildEnvironment
        Copy-TestResult -ProjectUri $buildEnv.ProjectUri -AccessToken $buildEnv.AccessToken -BuildUri $buildEnv.BuildUri -OutputFolder $buildEnv.CommonTestResultsFolder
    }
}

function Copy-TestResultToTemp {
    <#
     .SYNOPSIS
     Retrieves test results for SonarQube from the current Azure DevOps build and places them in the
     Common Test Results folder ($Agent.TempDirectory)/TestResults

     .DESCRIPTION
     Retrieves the test attachments from a build and places them in appropriate locations
     for SonarQube. This method expects the Azure DevOps environment variables to be set
     in order to automatically determine the location and build identity. This method calls
     Copy-TestResult using the appropriate Azure DevOps environment variables.

     .EXAMPLE
     Copy-TestResultToTemp
    #>
        [CmdletBinding()]
        param()
        process {
            $buildEnv = Get-BuildEnvironment
            Copy-TestResult -ProjectUri $buildEnv.ProjectUri -AccessToken $buildEnv.AccessToken -BuildUri $buildEnv.BuildUri -OutputFolder $buildEnv.TempTestResultsFolder
        }
}

function Copy-TestResult {
<#
 .SYNOPSIS
 Retrieves test results from a specific Azure DevOps build.

 .DESCRIPTION
 Retrieves the test attachments from a build and places them in a specified location.

 .PARAMETER ProjectUri
 The URI to the project root in Azure DevOps.

 .PARAMETER AccessToken
 The PAT token or authorization token to use for requesting the build details.

 .PARAMETER BuildUri
 The VSTFS URI for the build whose test results should be downloaded.

 .PARAMETER OutputFolder
 The location for storing the test results. Tests will be organized based on the expected
 folder conventions for SonarQube and the contents of any downloaded TRX files.

 .PARAMETER OutputFolderFormat
 The format string to use for creating child folders for the TRX file dependencies. The string can utilize a replacement variable, $folder,
 which indicates the folder path for a given dependency (as specified in the TRX file). A second variable, $trxFolder, is the safe folder
 based on the name of the TRX file. The default path is '$trxFolder/In/$folder'. Note that the path string should not be double-quoted
 when the replacement variables are used. All folder paths will be relative to OutputFolder.

 .EXAMPLE
 Copy-TestResult -ProjectUri https://dev.azure.com/myorg/project -AccessToken <PAT> -BuildUri vstfs:///Build/Build/1234 -OutputFolder c:\test-results -OutputFolderFormat 'In/$folder'
#>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipelineByPropertyName, Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Uri] $ProjectUri,

        [Parameter(ValueFromPipelineByPropertyName, Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $AccessToken,

        [Parameter(ValueFromPipelineByPropertyName, Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $BuildUri,

        [Parameter(ValueFromPipelineByPropertyName, Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $OutputFolder,

        [string] $OutputFolderFormat = '$trxFolder/In/$folder'
    )

    process {
        $ErrorActionPreference = "Stop"
        $tests = Get-TestRunList -BuildUri $BuildUri -BaseUri $ProjectUri -AccessToken $AccessToken
        if (-Not (Test-Path $OutputFolder)) {
            Write-Verbose "Creating output folder: '$OutputFolder'"
            [void](New-Item -ItemType Directory -Path $OutputFolder -Force)
        }

        foreach ($test in $tests) {
            $content = Get-GroupedAttachmentList -TestUri $test.url -AccessToken $AccessToken

            $trxFiles = $content.TrxContent
            $otherFiles = $content.OtherContent

            # Download TRX to get details about any related content locations
            foreach($item in $trxFiles) {
                Get-TestAttachment -AttachmentUri $item.url -OutputPath "$OutputFolder/$($item.fileName)" -AccessToken $AccessToken
            }

            $trxNodes = Get-TrxContent -Files $trxFiles -OutputFolder $OutputFolder -OutputFolderFormat $OutputFolderFormat
            # Create the required folders for child content
            foreach($node in $trxNodes) {
                if ($node) {
                    $path = [Path]::GetDirectoryName($node)
                    if ($path) {
                        Write-Verbose "Creating output location: '$path'"
                        [void](New-Item -ItemType Directory -Path $path -Force)
                    }
                }
            }

            # Download the reamining content
            $simpleFileList = $otherFiles | Select-Object -ExpandProperty 'fileName'
            $childLocations = Group-ChildContent -TrxContentList $trxNodes -FileList $simpleFileList -OutputFolder $OutputFolder
            foreach ($attachment in $otherFiles) {
                Write-Verbose "Downloading $($attachment.fileName)"
                $targetLocations = $childLocations[$attachment.FileName]
                $target = $targetLocations[0]
                Write-Verbose "Writing $($attachment.fileName) to $target"
                Get-TestAttachment -AttachmentUri $attachment.url -OutputPath $target -AccessToken $AccessToken

                if ($targetLocations.Length -gt 1){
                    foreach($dest in $targetLocations | Select-Object -Skip 1 ){
                        Write-Verbose "Writing $($attachment.fileName) to $dest"
                        [void](Copy-Item $target -Destination $dest -Force)
                    }
                }
            }
        }
    }
}

Export-ModuleMember -Function Copy-TestResult, Copy-TestResultToCommon, Copy-TestResultToTemp