[CmdletBinding()]
[OutputType([int])]
Param
(
    # determine what server to put in maintenance mode
    [Parameter(Mandatory=$true,
               ValueFromPipelineByPropertyName=$true,
               Position=0)]
    [string]$Server
)


$discoveredServer = Get-ExchangeServer -Identity $Server | Select IsHubTransportServer,IsFrontendTransportServer,AdminDisplayVersion

#Check for Administrative credentials
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")){
	Write-Warning "You do not have Administrator rights to run this script!`nPlease re-run this script as an Administrator!"
    Break
}

if($discoveredServer.AdminDisplayVersion.Major -ne "15"){
        Write-Warning "The specified Exchange Server is not an Exchange 2013 server!"
        Write-Warning "Aborting script..."
        Break
}


Write-Host "INFO: Reactivating all server components..." -ForegroundColor Yellow
    Set-ServerComponentState $server -Component ServerWideOffline -State Active -Requester Maintenance
Write-Host "INFO: Server component states changed back into active state using requester 'Maintenance'" -ForegroundColor Yellow

if($discoveredServer.IsHubTransportServer -eq $true){
                
    $mailboxserver = Get-MailboxServer -Identity $Server | Select DatabaseAvailabilityGroup
    
    if($mailboxserver.DatabaseAvailabilityGroup -ne $null){
        Write-Host "INFO: Server $server is a member of a Database Availability Group. Resuming the node now." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "INFO: Node information:" -ForegroundColor Green
        Write-Host "-----------------------" -ForegroundColor Green
        Invoke-Command -ComputerName $Server -ArgumentList $Server {Resume-ClusterNode $args[0]}
        Set-MailboxServer $Server -DatabaseCopyActivationDisabledAndMoveNow $false
        Set-MailboxServer $Server -DatabaseCopyAutoActivationPolicy Unrestricted
        Write-Host ""
        Write-Host ""
    }
    
    Write-Host "INFO: Resuming Transport Service..." -ForegroundColor Yellow
    Set-ServerComponentState –Identity $Server -Component HubTransport -State Active -Requester Maintenance

    Write-Host "INFO: Restarting the MSExchangeTransport Service on server $Server..." -ForegroundColor Yellow
    Invoke-Command -ComputerName $Server {Restart-Service MSExchangeTransport} | Out-Null

}

#restart FE Transport Services if server is also CAS
if($discoveredServer.IsFrontendTransportServer -eq $true){
    Write-Host "INFO: Restarting the MSExchangeFrontEndTransport Service on server $Server..." -ForegroundColor Yellow
    Invoke-Command -ComputerName $Server {Restart-Service MSExchangeFrontEndTransport} | Out-Null
}

Write-Host ""
Write-Host "INFO: Done! Server $server successfully taken out of Maintenance Mode." -ForegroundColor Green
Write-Host ""

$ComponentStates = (Get-ServerComponentstate $Server).LocalStates | ?{$_.State -eq "InActive"}
if($ComponentStates){
    Write-Warning "There are still some components inactive on server $Server."
    Write-Warning "Some features might not work until all components are back in an Active state."
    Write-Warning "Check the information below to see what components are still in an inactive state and which requester put them in that state."
    $ComponentStates
    Clear-Variable ComponentStates
}
