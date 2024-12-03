*** Settings ***
Resource            ../resources/common.resource

Test Setup          Setup Device
Test Teardown       Stop Device


*** Test Cases ***
Ignore Containers Marked With A Specific Label
    ${operation}=    Cumulocity.Execute Shell Command
    ...    text=sudo -E tedge-container engine docker run -d --label tedge.ignore=1 --network bridge --name manualapp10 docker.io/library/alpine:3.18 sleep infinity
    Cumulocity.Operation Should Be SUCCESSFUL    ${operation}
    Sleep    5s
    Should Have Services    service_type=container    name=manualapp10    max_count=0    min_count=0
