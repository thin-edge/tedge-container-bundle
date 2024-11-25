*** Settings ***
Library     Cumulocity
Library     DeviceLibrary    bootstrap_script=start-container-bundle.sh


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
    ${DEVICE_ID}=    DeviceLibrary.Setup    skip_bootstrap=${True}

    Transfer To Device    ${CURDIR}/../../test-images/common/container-bundle.sh    /usr/bin/
    Transfer To Device    ${CURDIR}/../*.tar.gz    /build/
    Execute Command    container-bundle.sh start ${DEVICE_ID} ${C8Y_CONFIG.host}

    Set Suite Variable    ${DEVICE_ID}
    Cumulocity.External Identity Should Exist    ${DEVICE_ID}

Stop Device
    DeviceLibrary.Execute Command    container-bundle.sh stop
    Cumulocity.Delete Managed Object And Device User    ${DEVICE_ID}
