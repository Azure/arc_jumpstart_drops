#####################################################################
### Akrii install
#####################################################################

# Install Akrii
$templateBaseUrl = "https://raw.githubusercontent.com/Azure/arc_jumpstart_drops/main/drops/sample_app/deploy_akri_and_mock_camera/"
$videoDir = ".\video"
helm repo add akri-helm-charts https://project-akri.github.io/akri/
helm repo update
helm install akri akri-helm-charts/akri `
--set onvif.discovery.enabled=true `
--set onvif.configuration.enabled=true `
--set onvif.configuration.capacity=2 `
--set onvif.configuration.brokerPod.image.repository='ghcr.io/project-akri/akri/onvif-video-broker' `
--set onvif.configuration.brokerPod.image.tag='latest'
 # Copy video scripts
Write-Host "Downloading video artifacts"

New-Item -Path $videoDir -ItemType directory -Force
Invoke-WebRequest ("https://jumpstartprodsg.blob.core.windows.net/video/akri_is_dope.mp4") -OutFile $videoDir\video.mp4  
Invoke-WebRequest ($templateBaseUrl + "artifacts/video/video-streaming.yaml") -OutFile $videoDir\video-streaming.yaml
Invoke-WebRequest ($templateBaseUrl + "artifacts/video/akri-video-streaming-app.yaml") -OutFile $videoDir\akri-video-streaming-app.yaml
kubectl apply -f $videoDir\akri-video-streaming-app.yaml
kubectl apply -f $videoDir\video-streaming.yaml  
