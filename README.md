# WebSpellChecker/WProofreader Helm Chart

This Helm chart provides all the basic infrastructure needed to deploy 
WProofreader Server to a Kubernetes cluster.
By default, the image is pulled from [WebSpellChecker Docker Hub](https://hub.docker.com/r/webspellchecker/wproofreader), 
however, many users would require building their own local images with custom configuration. 
Please refer to [our other repository](https://github.com/WebSpellChecker/wproofreader-docker/) to get started with building your own docker image.

## Prerequisites

Before you begin, make sure you have the required environment:

- Kubernetes command-line tool, [kubectl](https://kubernetes.io/docs/reference/kubectl/kubectl/)
- [Helm](https://helm.sh/docs/intro/quickstart/#install-helm), the package manager for Kubernetes

## Basic installation

The Chart can be installed the usual way using all the defaults:
```shell
git clone https://github.com/WebSpellChecker/wproofreader-helm.git
cd wproofreader-helm
helm install --create-namespace --namespace wsc wproofreader-app wproofreader 
```
where `wsc` is the namespace where the app should be installed,
`wproofreader-app` is the Helm release name, 
`wproofreader` is the local Chart directory.

API requests should be sent to the Kubernetes Service instance, reachable at
```text
http(s)://<service-name>.<namespace>.svc:<service-port>
```
where 
- `http` or `https` depends on the protocol used;
- `<service-name>` is the name of the Service instance, which would be `wproofreader-app` with the above 
command, unless overwritten using `fullnameOverride` `values.yaml` parameter;
- `<namespace>` is the namespace where the chart was installed;
- `.svc` can be omitted in most cases, but is recommended to keep;
- `<service-port>` is `80` or `443` by default for HTTP and HTTPS, respectively, 
in which case it can be omitted, unless explicitly overwritten with `service.port`
in `values.yaml`.

## License activation

There are three ways the service can be activated:
1. During `docker build` by setting the `LICENSE_TICKET_ID` argument in Dockerfile or CLI (`--build-arg LICENSE_TICKET_ID=${MY_LOCAL_VARIABLE}`).
2. Through the `values.yaml` config file (`licenseTicketID` parameter).
3. During chart deployment/upgrade CLI call using the flag:
```shell
--set licenseTicketID=${LICENSE_TICKET_ID}
```
provided that `LICENSE_TICKET_ID` is set in your environment.

> [!IMPORTANT]
> If you are attempting to build a production environment, it's recommended to use the custom Docker image with WProofreader Server instead of the public one published on Docker Hub. With the custom image, you won't need to activate the license on the container start. Thus, you just skip this step. Otherwise, you may face the issue with reaching the maximum allowed number of license activation attempts (by default, 25). In this case, you need to [contact support](https://webspellchecker.com/contact-us/) to extend/reset the license activation limit. Nevertheless, using the public image is acceptable for evaluation, testing and development purposes.

## HTTPS

By default, the server is set to communicate via HTTP, which is fine for 
communicating withing a closed network. For outbound connections it is of 
the utmost importance that clients communicate over TLS.

To do this, the following parameters have to change in `values.yaml`:
1. `useHTTPS` to `true`.
2. `certFile` and `keyFile` to relative paths of the certificate and key 
files within the chart directory. Keep in mind that Helm can't reach outside the chart directory.
3. `certMountPath` to whatever path was used in the `Dockerfile`.
For the DockerHub image, one should stick to the default value, which is `/certificate`.

> [!NOTE]
> `certFile` and `keyFile` filenames, as well as `certMountPath` have to match to values set in the 
> `Dockerfile` used for building the image. Otherwise, `nginx` config (`/etc/nginx/conf.d/wscservice.conf`) 
> has to be updated with new filenames and locations.
> The defaults for the DockerHub image are `cert.pem`, `key.pem`, and `/certificate`, respectively.

## Custom dictionaries

The Helm chart provides flexible options for managing custom dictionaries in your WProofreader Server deployment. There are several configuration scenarios to accommodate different use cases:

### Configuration options

**1. Dynamic persistent volume (PV) provisioning**

When `dictionaries.enabled` is set to `true` and neither `dictionaries.localPath` nor `dictionaries.existingClaim` storage configuration is provided, Kubernetes will dynamically provision a Persistent Volume based on `dictionaries.storageClass` that has to be defined externally.
This is the simplest way to manage custom dictionaries in a Kubernetes environment:
```yaml
dictionaries:
  enabled: true
  storageClass: "efs-sc"
```

> [!IMPORTANT]
> Ensure that the specified storageClass supports the required access mode (typically `ReadWriteMany`).
> Not all volume plugins (CSI drivers) support all access modes — for example, block storage types like AWS EBS support only `ReadWriteOnce`, while shared file systems like Amazon EFS support `ReadWriteMany`.
>
> Read your storage provider’s CSI driver documentation to confirm compatibility before relying on dynamic provisioning.

**2. hostPath volume (node-local storage)**

Use this option if you prefer mounting dictionaries from the local filesystem of a specific node. 
This is useful when you have a single-node cluster or need to share dictionaries across multiple pods running on the same node.

To enable WProofreader Server to use your custom dictionaries with Kubernetes `hostPath` storage type, follow these steps:
1. Upload the files to a directory on the node where the chart will be deployed.
   Ensure this node has `wproofreader.domain-name.com/app` label.
2. Set `dictionaries.localPath` parameter to the absolute path of this directory.
3. Optionally, edit `dictionaries.mountPath` value if a non-default one was used in `Dockerfile`,
as well as other `dictionaries` parameters if needed.
4. Install the chart as usual.

The Chart uses `nodeAffinity` for mounting Persistent Volume of type `local`.
This allows the user to specify which node will host WProofreader Server 
on a cluster, even a single-node one.

To assign this role to a node, you need to attach a label to it. It can be any label you choose,
e.g., `wproofreader.domain-name.com/app`:
```shell
kubectl label node <node-name> wproofreader.domain-name.com/app=
```
Note that `=` is required but the value after it is not important (empty in this example).

Keep in mind that your custom label has to be either updated in `values.yaml`
(`nodeAffinityLabel` key, recommended), or passed to `helm` calls using 
`--set nodeAffinityLabel=wproofreader.domain-name.com/app`.

Example `values.yaml` configuration:
```yaml
nodeAffinityLabel: "wproofreader.domain-name.com/app"

dictionaries:
  enabled: true
  localPath: "/dictionaries"
```

To install the Chart with the custom dictionaries feature enabled and the local path set to the directory on the node where dictionaries are stored:
```shell
helm install --create-namespace --namespace wsc wproofreader-app wproofreader \
  --set nodeAffinityLabel=wproofreader.domain-name.com/app \
  --set dictionaries.enabled=true \
  --set dictionaries.localPath=/dictionaries
```
The dictionary files can be uploaded after the chart installation, but the `dictionaries.localPath` 
folder must exist on the node beforehand. 
Dictionaries can be uploaded to the node VM using standard methods (`scp`, `rsync`, `FTP`, etc.) or 
the `kubectl cp` command. With `kubectl cp`, you need to use one of the deployment's pods. 
Once uploaded, the files will automatically appear on all pods and persist
even if the pods are restarted. Follow these steps:
1. Get the name of one of the pods. For the Helm release named `wproofreader-app` in the `wsc` namespace, use
   ```shell
   POD=$(kubectl get pods -n wsc -l app.kubernetes.io/instance=wproofreader-app -o jsonpath="{.items[0].metadata.name}")
   ```
2. Upload the files to the pod
   ```shell
   kubectl cp -n wsc <local path to files> $POD:/dictionaries
   ```
   Replace `/dictionaries` with your custom `dictionaries.mountPath` value if applicable.
   
**3. Existing Persistent Volume Claim (PVC)**

There is also a way in the Chart to specify an already existing Persistent Volume Claim (PVC) with dictionaries that can be configured to operate on multiple nodes (e.g., NFS). To do this, enable the custom dictionary feature by setting the `dictionaries.enabled` parameter to `true` and specifying the name of the existing PVC in the `dictionaries.existingClaim` parameter.
```yaml
dictionaries:
  enabled: true
  existingClaim: "wproofreader-dictionaries-pvc"
```

**4. Default behavior**

If `dictionaries.enabled` is `false`, the chart will use an ephemeral `emptyDir` volume for `/dictionaries`.
This means any uploaded dictionaries will be lost after pod restarts. 
This setup is only suitable for development and testing.

> [!TIP]
> Using an existing PVC is the recommended way because it ensures that your data will persist even if the Chart is uninstalled. This approach offers a reliable method to maintain data integrity and availability across deployments.
>
> However, please note that provisioning the Persistent Volume (PV) and PVC for storage backends like NFS is outside the scope of this Chart. You will need to provision the PV and PVC separately according to your storage backend's documentation before using the `dictionaries.existingClaim` parameter.

## Use in production

For production deployments, it is highly recommended **to specify resource requests and limits for your Kubernetes pods**. This helps ensure that your applications have the necessary resources to run efficiently while preventing them from consuming excessive resources on the cluster which can impact other applications.
This can be configured in the `values.yaml` file under the `resources` section.

### Recommended resource requests and limits

Below are the recommended resource requests and limits for deploying WProofreader Server v5.34.x with enabled English dialects (en_US, en_GB, en_CA, and en_AU) for spelling & grammar check using the English AI language model for enhanced and more accurate proofreading. It also includes such features as a style guide, spelling autocorrect, named-entity recognition (NER), and text autocomplete suggestions (text prediction). These values represent the minimum requirements for running WProofreader Server in a production environment.

```yaml
resources:
  requests:
    memory: "4Gi"
    cpu: "1"
  limits:
    memory: "8Gi"
    cpu: "4"
```

> [!NOTE]
> Depending on your specific needs and usage patterns, especially when deploying AI language models for enhanced proofreading in other languages, you may need to adjust these values to ensure optimal performance and resource utilization. Alternatively, you can choose the bare-minimum configuration without AI language models. In this case, only algorithmic engines will be used to provide basic spelling and grammar checks.

### Readiness and liveness probes

The Helm chart includes readiness and liveness probes to help Kubernetes manage the lifecycle of the WProofreader Server pods. These probes are used to determine when the pod is ready to accept traffic and when it should be restarted if it becomes unresponsive.

You may thoughtfully modify the Chart default values based on your environment's resources and application needs in the `values.yaml` file under the `readinessProbeOptions` and `livenessProbeOptions` sections.
Example:
```yaml
readinessProbeOptions:
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 5
  successThreshold: 1
  failureThreshold: 3
```

### Application scaling
WProofreader Server can be scaled horizontally by changing the number of replicas.
This can be done by setting the `replicaCount` parameter in the `values.yaml` file. 
The default value is `1`. For example, to scale the application to 3 replicas, set the `--set replicaCount=3` flag when installing the Helm chart.

For dynamic scaling based on resource utilization, you can use Kubernetes Horizontal Pod Autoscaler (HPA). 
To use the HPA, you need to turn on the metrics server in your Kubernetes cluster. The HPA will then automatically change the number of pods in a deployment based on how much CPU is being used.
The HPA is not enabled by default in the Helm chart. To enable it, set the `autoscaling.enabled` parameter to `true` in the `values.yaml` file.

> [!IMPORTANT]
> WProofreader Server can be scaled only based on CPU usage metric. The `targetMemoryUtilizationPercentage` is not supported.

## Common issues
### Readiness probe failed

Check the pod logs to see if the license ID has not been provided:
```shell
POD=$(kubectl get pods -n <namespace> -l app.kubernetes.io/instance=<release-name> -o jsonpath="{.items[0].metadata.name}")
kubectl logs -n <namespace> $POD
```

If so, refer to [license section](#license-activation). 
Existing release can be patched with
```shell
helm upgrade -n <namespace> <release-name> wproofreader --set licenseTicketID=<license ID> 
```

Keep in mind, that upcoming `helm upgrade` have to carry on the `licenseTicketID` flag, 
so that it's not overwritten with the (empty) value from `values.yaml`.

### Something got broken following helm upgrade

Please make sure that all values arguments passed as `--set` CLI arguments 
were duplicated with your latest `helm upgrade` call, or simply use `--reuse-values` flag. 
Otherwise, they are overwritten with the contents of `values.yaml`.

## Sample Kubernetes manifests

For illustration purposes, please find exported Kubernetes manifests in the `manifests` folder.
If you need to export the manifest files from this sample Helm Chart, please use the following command:
```shell
helm template --namespace wsc wproofreader-app wproofreader \
  --set licenseTicketID=qWeRtY123 \
  --set useHTTPS=true \
  --set certFile=cert.pem \
  --set keyFile=key.pem \
  --set dictionaries.localPath=/var/local/dictionaries \
  > manifests/manifests.yaml
```

## Troubleshooting

The service might fail to start up properly if misconfigured. For troubleshooting, it can be beneficial to get the full configuration you attempted to deploy. If needed, later it can be shared with the support team for further investigation.

There are several ways to gather necessary details:
1. Get the values (user-configurable options) used by Help to generate Kubernetes manifests:
```shell
helm get values --all --namespace wsc wproofreader-app > wproofreader-app-values.yaml
```
where `wsc` is the namespace and `wproofreader-app` – the name of your release, 
and `wproofreader-app-values.yaml` – name of the file the data will be written to.

2. Extract the full Kubernetes manifest(s) as follows:
```shell
helm get manifest --namespace wsc wproofreader-app > manifests.yaml
```

If you do not have access to `helm`, same can be accomplished using 
`kubectl`. To get manifests for all resources in the `wsc` namespace, run:
```shell
kubectl get all --namespace wsc -o yaml > manifests.yaml
```
3. Retrieve the logs of all `wsproofreader-app` pods in the `wsc` namespace:
```shell
kubectl logs -n wsc -l app.kubernetes.io/instance=wproofreader-app
```