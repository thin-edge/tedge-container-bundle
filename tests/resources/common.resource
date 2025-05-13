*** Settings ***
Library     Cumulocity
Library     DeviceLibrary    bootstrap_script=/dev/null


*** Variables ***
# Cumulocity settings
&{C8Y_CONFIG}
...                 host=%{C8Y_BASEURL= }
...                 username=%{C8Y_USER= }
...                 password=%{C8Y_PASSWORD= }
...                 tenant=%{C8Y_TENANT= }

# Docker adapter settings (to control which image is used in the system tests).
# The user just needs to set the IMAGE env variable
&{DOCKER_CONFIG}    image=%{TEST_IMAGE=}


*** Keywords ***
Setup Device
    [Arguments]    ${image}=
    ${DEVICE_ID}=    DeviceLibrary.Setup    skip_bootstrap=${True}

    Transfer To Device    ${CURDIR}/../../test-images/common/container-bundle.sh    /usr/bin/
    Transfer To Device    ${CURDIR}/../*.tar.gz    /build/
    ${credentials}=    Cumulocity.Bulk Register Device With Cumulocity CA    external_id=${DEVICE_ID}    name=${DEVICE_ID}
    Execute Command
    ...    container-bundle.sh start --device-id '${DEVICE_ID}' --c8y-url '${C8Y_CONFIG.host}' --one-time-password '${credentials.one_time_password}' --image "${image}" --debug 2>&1

    Set Suite Variable    ${DEVICE_ID}
    Cumulocity.External Identity Should Exist    ${DEVICE_ID}

Stop Device
    DeviceLibrary.Execute Command    container-bundle.sh stop --device-id '${DEVICE_ID}' --debug
    Cumulocity.Delete Managed Object And Device User    ${DEVICE_ID}
