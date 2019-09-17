Set-StrictMode -Version 'Latest'
#Requires -Version 5.0

$moduleName = $MyInvocation.MyCommand.Name -replace '.tests.ps1'
$testRoot = (Split-Path -Parent $MyInvocation.MyCommand.Path)
$scriptRoot = $testRoot -replace 'tests','src'
Get-Module $moduleName | Remove-Module -Force
Import-Module "$scriptRoot/$moduleName.psm1" -Force

InModuleScope $moduleName {
    Describe "Invoke-WebRequestWithRetry" {
        Context "Given that failing request is called with a 2 retries" {
            Mock -CommandName Invoke-WebRequest -Verifiable -MockWith {
                Throw 'Invalid response'
            }

            It "Should call the function exactly 3 times" {
                {
                    Invoke-WebRequestWithRetry -Parameters @{Uri = 'http://any' } `
                        -MaxRetries 2 `
                        -SleepTime 10
                } | Should -Throw -ExceptionType "System.InvalidOperationException"
                Assert-MockCalled Invoke-WebRequest -Exactly 3 -Scope It
            }
        }

        Context "Given that a request is called successfully" {
            Mock -CommandName Invoke-WebRequest -Verifiable -MockWith {
                return @{
                    StatusCode = 200
                    Content    = "Good content"
                }
            }

            It "Should call the function exactly 1 times" {
                $result = Invoke-WebRequestWithRetry -Parameters @{Uri = 'http://any' } `
                    -MaxRetries 2 `
                    -SleepTime 10
                Assert-MockCalled Invoke-WebRequest -Exactly 1 -Scope It
            }
        }
    }

    Describe "Get-TestRunList" {
        Context "Invoking a request" {
            Mock -CommandName Invoke-WebRequest -Verifiable -MockWith {
                return @{
                    Content = '{"value":"Value" }'
                }
            }

            $result = Get-TestRunList -BuildUri 'nnn' -BaseUri 'urn://ne' -AccessToken '1234'

            It "Should automatically include  JSON content type" {
                Assert-MockCalled Invoke-WebRequest -ParameterFilter { $Headers.Item('Accept') -eq 'application/json' } -Exactly -Times 1 -Scope Context
            }

            It "Should automatically include an authorization header" {
                Assert-MockCalled -CommandName Invoke-WebRequest -ParameterFilter { $Headers.Item('Authorization') -eq 'Basic OjEyMzQ=' } -Exactly -Times 1 -Scope Context
            }

            It "Should use an HTTP GET" {
                Assert-MockCalled -CommandName Invoke-WebRequest -ParameterFilter { $Method -eq 'Get' } -Exactly -Times 1 -Scope Context
            }
        }
    }

    Describe "Get-TestAttachmentList" {
        Context "Invoking a request" {
            Mock -CommandName Invoke-WebRequest -Verifiable -MockWith {
                return @{
                    Content = '{"value":"Value" }'
                }
            }

            [void](Get-TestAttachmentList -TestUri 'urn://ne' -AccessToken '1234')

            It "Should automatically include  JSON content type" {
                Assert-MockCalled Invoke-WebRequest -ParameterFilter { $Headers.Item('Accept') -eq 'application/json' } -Exactly -Times 1 -Scope Context
            }

            It "Should automatically include an authorization header" {
                Assert-MockCalled -CommandName Invoke-WebRequest -ParameterFilter { $Headers.Item('Authorization') -eq 'Basic OjEyMzQ=' } -Exactly -Times 1 -Scope Context
            }

            It "Should use an HTTP GET" {
                Assert-MockCalled -CommandName Invoke-WebRequest -ParameterFilter { $Method -eq 'Get' } -Exactly -Times 1 -Scope Context
            }
        }
    }

    Describe "Group-TestAttachmentList" {

		Context "Given a request that contains multiple TRX and coverage files" {
	        $samplesRoot = "$PSScriptRoot/samples/api"

			$content = [string](Get-Content -Encoding UTF8 -ReadCount 0 -Path "$samplesRoot/RunWithMultipleTrxAndCoverage.json")
			$data = [PSCustomObject[]]((ConvertFrom-Json -InputObject $content).value)
			$results = $data | Group-TestAttachmentList

			It "Should not have null results" {
				$results | Should Not Be $null
			}

			It "Should identify multiple TRX files" {
				$results.TrxContent.Length | Should Be 2
			}

			It "Should identify non-TRX Content" {
				$results.OtherContent.Length | Should Be 2
			}
		}
    }

    Describe "Get-TrxContent" {

		Context "Given a TRX file containing two coverage files" {

            $trxFiles = @(
                @{
                    fileName = 'simple file.trx'
                    url = 'urn://org/project/api/path'
                }
            )
            Mock -CommandName Get-TestAttachment -Verifiable -MockWith {
            }

            Mock -CommandName Get-TrxAttachmentList -Verifiable -MockWith {
                @(
                    ('agent{0}DeplRoot_agent 2019-08-25 05_47_09.coverage' -f [IO.Path]::DirectorySeparatorChar),
                    ('agent{0}DeplRoot_agent 2019-08-25 05_47_10.coverage' -f [IO.Path]::DirectorySeparatorChar)
                )
            }

            $results = Get-TrxContent -Files $trxFiles -OutputFolder '/root'
            $results | Format-List

			It "Should not have null results" {
				$results | Should Not Be $null
			}

			It "Should have two children" {
				$results.Length | Should Be 2
			}

			It "Should map the 09 coverage file correctly" {
				$results | Should Contain ([Path]::GetFullPath('/root/simple_file/In/agent/DeplRoot_agent 2019-08-25 05_47_09.coverage'))
            }

            It "Should map the 10 coverage file correctly" {
				$results | Should Contain ([Path]::GetFullPath('/root/simple_file/In/agent/DeplRoot_agent 2019-08-25 05_47_10.coverage'))
            }
        }

        Context "Given a TRX file containing two coverage files and an empty output path" {

            $trxFiles = @(
                @{
                    fileName = 'simple file.trx'
                    url = 'urn://org/project/api/path'
                }
            )
            Mock -CommandName Get-TestAttachment -Verifiable -MockWith {
            }

            Mock -CommandName Get-TrxAttachmentList -Verifiable -MockWith {
                @(
                    ('agent{0}DeplRoot_agent 2019-08-25 05_47_09.coverage' -f [IO.Path]::DirectorySeparatorChar),
                    ('agent{0}DeplRoot_agent 2019-08-25 05_47_10.coverage' -f [IO.Path]::DirectorySeparatorChar)
                )
            }

            $results = Get-TrxContent -Files $trxFiles -OutputFolder '/root' -TrxDependencyPath ''
            $results | Format-List

			It "Should not have null results" {
				$results | Should Not Be $null
			}

			It "Should have two children" {
				$results.Length | Should Be 2
			}

			It "Should map the 09 coverage file correctly" {
				$results | Should Contain ([Path]::GetFullPath('/root/DeplRoot_agent 2019-08-25 05_47_09.coverage'))
            }

            It "Should map the 10 coverage file correctly" {
				$results | Should Contain ([Path]::GetFullPath('/root/DeplRoot_agent 2019-08-25 05_47_10.coverage'))
            }
        }

        Context "Given a TRX file containing two coverage files and a defined output path with a folder" {

            $trxFiles = @(
                @{
                    fileName = 'simple file.trx'
                    url = 'urn://org/project/api/path'
                }
            )
            Mock -CommandName Get-TestAttachment -Verifiable -MockWith {
            }

            Mock -CommandName Get-TrxAttachmentList -Verifiable -MockWith {
                @(
                    ('agent{0}DeplRoot_agent 2019-08-25 05_47_09.coverage' -f [IO.Path]::DirectorySeparatorChar),
                    ('agent{0}DeplRoot_agent 2019-08-25 05_47_10.coverage' -f [IO.Path]::DirectorySeparatorChar)
                )
            }

            $results = Get-TrxContent -Files $trxFiles -OutputFolder '/root' -TrxDependencyPath '$trxFolder/$folder'
            $results | Format-List

			It "Should not have null results" {
				$results | Should Not Be $null
			}

			It "Should have two children" {
				$results.Length | Should Be 2
			}

			It "Should map the 09 coverage file correctly" {
				$results | Should Contain ([Path]::GetFullPath('/root/simple_file/agent/DeplRoot_agent 2019-08-25 05_47_09.coverage'))
            }

            It "Should map the 10 coverage file correctly" {
				$results | Should Contain ([Path]::GetFullPath('/root/simple_file/agent/DeplRoot_agent 2019-08-25 05_47_10.coverage'))
            }
		}
    }

	Describe "Group-ChildContent" {

		Context "Given a multiple TRX and coverage files" {

            $trxChildPaths = @(
                'x:/root/trx_1/In/node/file11.coverage',
                'x:/root/trx_1/In/node/file12.coverage',
                'x:/root/trx_2/In/node/file21.coverage',
                'x:/root/trx_2/In/node/file22.coverage',
                'x:/root/trx_2/Src/node/file22.coverage'
            )

            $fileList = @(
               'random.txt',
               'file11.coverage',
               'file12.coverage',
               'file21.coverage',
               'file22.coverage'
            )

			$fileList | Format-Table
            $results = Group-ChildContent -TrxContentList $trxChildPaths -FileList $fileList -OutputFolder 'x:/root/'

			It "Should not have null results" {
				$results | Should Not Be $null
			}

			It "File11 should be in proper location" {
				$results['file11.coverage'] | Should Contain 'x:/root/trx_1/In/node/file11.coverage'
            }

            It "File12 should be in proper location" {
				$results['file12.coverage'] | Should Contain 'x:/root/trx_1/In/node/file12.coverage'
			}

			It "File21 should be in primary location" {
				$results['file21.coverage'] | Should Contain 'x:/root/trx_2/In/node/file21.coverage'
            }

            It "File22 should be in proper secondary location" {
				$results['file22.coverage'] | Should Contain 'x:/root/trx_2/Src/node/file22.coverage'
            }

            It "File22 should be in proper non-node location" {
				$results['file22.coverage'] | Should Contain 'x:/root/trx_2/In/node/file22.coverage'
			}
		}
    }

    Describe "Get-TrxAttachmentList" {
        $samplesRoot = "$PSScriptRoot/samples/trx"

        Context "Given a TRX file with with an attachment in a folder" {

            $trx = "$samplesRoot/SampleWithFolder.trx"
            $results = Get-TrxAttachmentList -FilePath $trx

            It "Should correctly count the nodes" {
                ($results | Measure).Count | Should Be 1
            }

            It "Should return the names of the files" {
                $results | Select -First 1 | Should Be 'agent\DeplRoot_agent 2019-08-25 05_47_09.coverage'
            }
        }

        Context "Given a TRX file with with an attachment not in a folder" {

            $trx = "$samplesRoot/SampleWithoutFolder.trx"
            $results = Get-TrxAttachmentList -FilePath $trx

            It "Should correctly count the nodes" {
                ($results | Measure).Count | Should Be 1
            }

            It "Should return the names of the files" {
                $results | Select -First 1 | Should Be 'DeplRoot_agent 2019-08-25 05_47_09.coverage'
            }
        }

        Context "Given a TRX file with with no attachments" {

            $trx = "$samplesRoot/SampleWithoutAttachment.trx"
            $results = Get-TrxAttachmentList -FilePath $trx

            It "Should be empty" {
                $results | Should Be @()
            }
        }
    }

    Describe "Get-TestAttachment" {
        Context "Given a new request" {
            Mock -CommandName Invoke-WebRequest -Verifiable -MockWith {
                return @{
                    Content = '{"value":"Value" }'
                }
            }

            $result = Get-TestAttachment -AttachmentUri 'urn://ne' -AccessToken '1234' -OutputPath New-TemporaryFile.FullName

            It "Should not include JSON content type" {
                Assert-MockCalled Invoke-WebRequest -ParameterFilter { $Headers.Item('Accept') -eq 'application/json' } -Exactly -Times 0 -Scope Context
            }

            It "Should automatically include an authorization header" {
                Assert-MockCalled -CommandName Invoke-WebRequest -ParameterFilter { $Headers.Item('Authorization') -eq 'Basic OjEyMzQ=' } -Exactly -Times 1 -Scope Context
            }

            It "Should use an HTTP GET" {
                Assert-MockCalled -CommandName Invoke-WebRequest -ParameterFilter { $Method -eq 'Get' } -Exactly -Times 1 -Scope Context
            }
        }
    }
}

Describe 'Script Analyzer Rules' {
    $scriptsModules = Get-ChildItem $scriptRoot -Include *.psd1, *.psm1, *.ps1 -Exclude *.tests.ps1 -Recurse
    Context "Checking files to test exist and Invoke-ScriptAnalyzer cmdLet is available" {
        It "Checking files exist to test." {
            ($scriptsModules | Measure).Count | Should Not Be 0
        }
        It "Checking Invoke-ScriptAnalyzer exists." {
            { Get-Command Invoke-ScriptAnalyzer -ErrorAction Stop } | Should Not Throw
        }
    }

    $scriptAnalyzerRules = Get-ScriptAnalyzerRule

    forEach ($scriptModule in $scriptsModules) {
        switch -wildCard ($scriptModule) {
            '*.psm1' { $typeTesting = 'Module' }
            '*.ps1' { $typeTesting = 'Script' }
            '*.psd1' { $typeTesting = 'Manifest' }
        }

        Context "Checking $typeTesting – $($scriptModule) - conforms to Script Analyzer Rules" {
            forEach ($scriptAnalyzerRule in $scriptAnalyzerRules) {
                It "Script Analyzer Rule $scriptAnalyzerRule" {
                    (Invoke-ScriptAnalyzer -Path $scriptModule -IncludeRule $scriptAnalyzerRule | Measure).Count | Should Be 0
                }
            }
        }
    }
}