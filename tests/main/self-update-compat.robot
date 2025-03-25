*** Settings ***
Resource            ../resources/common.resource
Library             DateTime

Test Teardown       Stop Device

# Retry due to a problem with the older tedge-container-bundle images
Test Tags           self-update    test:retry(3)


*** Test Cases ***
Update From Legacy Versions
    [Template]    Upgrade From Base Image
    ghcr.io/thin-edge/tedge-container-bundle:20241126.1855


*** Keywords ***
Upgrade From Base Image
    [Arguments]    ${IMAGE}
    # pre-condition
    Setup Device    image=${IMAGE}

    ${major_version}=    Execute Command
    ...    podman --version | cut -d' ' -f3 | cut -d. -f1
    ...    ignore_exit_code=${True}
    ...    strip=${True}
    Skip If    '${major_version}' == '4'    Legacy images didn't support podman 4.x

    Device Should Have Installed Software
    ...    {"name": "tedge", "version": "${IMAGE}", "softwareType": "self"}    timeout=10

    ${operation}=    Cumulocity.Install Software
    ...    {"name": "tedge", "version": "ghcr.io/thin-edge/tedge-container-bundle:99.99.1", "softwareType": "self"}

    Cumulocity.Operation Should Be SUCCESSFUL    ${operation}    timeout=180
    Device Should Have Installed Software
    ...    {"name": "tedge", "version": "ghcr.io/thin-edge/tedge-container-bundle:99.99.1", "softwareType": "container"}
