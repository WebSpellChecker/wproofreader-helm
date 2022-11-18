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

The chart uses `nodeAffinity` for mounting Persistent Volume of type `local`.
This also allows the user to specify which node will host the WProofreader Server 
on a cluster (even a single-node one).

To assign this role to a node, one has to attach a label to it. It can be whatever you want it to be,
e.g. `proofreader.your-company.com/app`:
```shell
kubectl label node <name-of-the-node> proofreader.company-domain.com/app=
```
Note that `=` is required, but the value after it is not important (empty in this example).

Keep in mind that your custom label has to be either updated in `values.yaml`
(`affinityLabel` key, recommended), or passed to `helm` calls using 
`--set affinityLabel=proofreader.company-domain.com/app`.

Now, the chart can be installed the usual way using all the defaults:
```shell
git clone https://github.com/WebSpellChecker/wproofreader-helm.git
cd wproofreader-helm
helm install --create-namespace --namespace wsc wsc-app-5-x-x wproofreader --set affinityLabel=proofreader.company-domain.com/app 
```
where `wsc` is the namespace the app should be installed to,
`wsc-app-5-25-0` – the release name, where we specifically mention the product version 5.25.0, 
`wproofreader` – local chart directory, 
`--set affinityLabel=proofreader.company-domain.com/app` – optional affinity label, see previous paragraph.

API requests should be sent to the Kubernetes Service instance, reachable at
```text
http(s)://<service-name>.<namespace>.svc:<service-port>
```
where 
- `http` or `https` depends on the protocol used;
- `<service-name>` is the name of the Service instance, which would be `wsc-app-5-25-0-wproofreader` with the above 
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

IMPORTANT! If you are attempting to build a production environment, it's recommended to use the custom Docker image with WProofreader Server instead of the public one published on Docker Hub. With the custom image, you won't need to activate the license on the container start. Thus, you just skip this step. Otherwise, you may face the issue with reaching the maximum allowed number of license activation attempts (by default, 25). In this case, you need to [contact support](https://webspellchecker.com/contact-us/) to extend/reset the license activation limit. Nevertheless, using the public image is acceptable for evaluation, testing and development purposes.

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

Note: `certFile` and `keyFile` filenames, as well as `certMountPath` have to match to values set in the 
`Dockerfile` used for building the image. Otherwise, `nginx` config (`/etc/nginx/conf.d/wscservice.conf`) 
has to be updated with new filenames and locations.
The defaults for the DockerHub image are `cert.pem`, `key.pem`, and `/certificate`, respectively.

## Custom dictionaries

To allow WProofreader Server to use your custom dictionaries, you have to do the following:
1. Upload the files to some directory on the node, where the chart will be deployed
   (remember, it's the one with the `proofreader.company-domain.com/app` label).
2. Set `dictionaries.localPath` parameter to the absolute path of this directory.
3. Optionally, edit `dictionaries.mountPath` value if non-default one was used in `Dockerfile`,
as well as other `dictionaries` parameters if needed.
4. Install the chart normally.

The dictionary files can be uploaded after the chart installation, but the `dictionaries.localPath` 
folder has to exist on the node beforehand. 
Dictionaries can be uploaded to the node VM either the usual way (`scp`, `rsync`, `FTP` etc), or 
using `kubectl cp` command. With `kubectl cp` we have to use one of pods of the deployment. 
Once the files are uploaded, they will appear on all the pods automatically, and will persist 
if any or all the pods are restarted. The workflow for this would look something like this:
1. Get the name of one of the pods. For the Helm release named `wsc-app-5-25-0` installed in the `wsc` namespace, we can use
   ```shell
      POD=$(kubectl get pods -n wsc -l app.kubernetes.io/instance=wsc-app-5-25-0 -o jsonpath="{.items[0].metadata.name}")
   ```
2. Upload the files to the pod
   ```shell
      kubectl cp -n wsc <local path to files> $POD:/dictionaries
   ```
   where `/dictionaries` should be changed to whatever non-default `dictionaries.mountPath` value was used if applicable.
   
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

Keep in mind, that upcoming `helm upgrade`'s have to carry on the `licenseTicketID` flag, 
so that it's not overwritten with the (empty) value from `values.yaml`.

### Something got broken following `helm upgrade`

Please make sure that all values arguments passed as `--set` CLI arguments 
were duplicated with your latest `helm upgrade` call, or simply use `--reuse-values` flag. 
Otherwise, they are overwritten with the contents of `values.yaml`.

## Sample Kubernetes manifests

For illustration purposes, please find exported Kubernetes manifests in the `manifests` folder.
If you need to export the manifest files from this sample Helm Chart, please use the following command:
```shell
helm template --namespace wsc wsc-app-sample wproofreader \
  --set licenseTicketID=qWeRtY123 \
  --set useHTTPS=true \
  --set certFile=cert.pem \
  --set keyFile=key.pem \
  --set dictionaries.localPath=/var/local/dictionaries \
  > manifests/manifests.yaml
```

## Troubleshooting

The service might fail to start up properly if misconfigured. For troubleshooting, it can be beneficial to get the full configuration you attempted to deploy. If needed, later it can be shared with the support team for further investigation.

There are several options for how to gather needed details:
1. Get the values (user-configurable options) used by Help to generate Kubernetes manifests:
```shell
helm get values --all --namespace wsc wsc-app-5-25-0 > wsc-app-5-25-0-values.yaml
```
where `wsc` is the namespace and `wsc-app-5-25-0` – the name of your release, 
and `wsc-app-5-25-0-values.yaml` – name of the file the data will be written to.

Extract the full Kubernetes manifest(s) as follows:
```shell
helm get manifest --namespace wsc wsc-app-5-25-0 > manifests.yaml
```

If, for any reason, you do not have access to `helm`, same can be accomplished using 
`kubectl`. To get manifests for all resources in `wsc` namespace, use:
```shell
kubectl get all --namespace wsc -o yaml > manifests.yaml
```