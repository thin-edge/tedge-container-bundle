*** Settings ***
Resource            ../resources/common.resource
Library             DateTime

Suite Setup         Setup Device
Suite Teardown      Stop Device


*** Test Cases ***
Grace period to allow container to startup
    Sleep    5s    reason=Wait for container to startup

Service is up
    Cumulocity.Should Have Services    name=tedge-container-plugin    status=up    max_count=1

Restart device
    Skip
    ${date_from}=    Get Test Start Time
    Sleep    1s
    ${operation}=    Cumulocity.Restart Device
    Operation Should Be SUCCESSFUL    ${operation}    timeout=120

Get Logfile Request
    [Template]    Get Logfile Request
    software-management

Get Configuration File
    [Template]    Get Configuration File
    tedge.toml
    system.toml

Set Configuration File
    ${binary_url}=    Create Inventory Binary    tedge-configuration-plugin.toml    toml    file=${CURDIR}/files/tedge-configuration-plugin.v2.toml
    ${operation}=    Set Configuration    tedge-configuration-plugin    url=${binary_url}
    Operation Should Be SUCCESSFUL    ${operation}

Execute Shell Command
    ${operation}=    Cumulocity.Execute Shell Command    ls -l /etc/tedge
    Cumulocity.Operation Should Be SUCCESSFUL    ${operation}

Install application using docker compose
    ${file_url}=    Cumulocity.Create Inventory Binary
    ...    nodered
    ...    docker-compose
    ...    file=${CURDIR}/files/docker-compose.nodered.yaml
    ${operation}=    Cumulocity.Install Software
    ...    {"name": "nodered-instance1", "version": "1.0.0", "softwareType": "container-group", "url": "${file_url}"}
    Cumulocity.Operation Should Be SUCCESSFUL    ${operation}    timeout=60
    ${software}=    Device Should Have Installed Software
    ...    {"name": "nodered-instance1", "version": "1.0.0", "softwareType": "container-group"}

    Cumulocity.Should Have Services
    ...    service_type=container-group
    ...    name=nodered-instance1@node-red
    ...    status=up
    ...    max_count=1

Get Container Logs
    ${operation}=    Cumulocity.Get Log File    container    search_text=tedge    maximum_lines=100
    Cumulocity.Operation Should Be SUCCESSFUL    ${operation}

Get Container Logs without explicit container name
    ${operation}=    Cumulocity.Get Log File    container    maximum_lines=100
    Cumulocity.Operation Should Be SUCCESSFUL    ${operation}

Get Container Logs For Non-existent container
    ${operation}=    Cumulocity.Get Log File    container    search_text=does-not-exist    maximum_lines=100
    Cumulocity.Operation Should Be Failed    ${operation}


*** Keywords ***
Get Configuration File
    [Arguments]    ${typename}
    ${operation}=    Cumulocity.Get Configuration    ${typename}
    Cumulocity.Operation Should Be SUCCESSFUL    ${operation}

Get Logfile Request
    [Arguments]    ${name}
    ...    ${search_text}=
    ...    ${max_lines}=1000
    ${start_timestamp}=    DateTime.Get Current Date    UTC    -24 hours    result_format=%Y-%m-%dT%H:%M:%S+0000
    ${end_timestamp}=    Get Current Date    UTC    +60 seconds    result_format=%Y-%m-%dT%H:%M:%S+0000
    ${operation}=    Cumulocity.Create Operation
    ...    description=Get Log File: ${name}
    ...    fragments={"c8y_LogfileRequest": {"dateFrom":"${start_timestamp}","dateTo":"${end_timestamp}","logFile":"${name}","maximumLines":${max_lines},"searchText":"${search_text}"}}
    ${operation}=    Operation Should Be SUCCESSFUL    ${operation}
    Should Not Be Empty    ${operation["c8y_LogfileRequest"]["file"]}
