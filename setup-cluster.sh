#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: 2022 Buoyant Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Copyright 2022 Buoyant Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License.  You may obtain
# a copy of the License at
#
#     http:#www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

# FOR THIS TO WORK, you will need:
# - your ngrok API key in $HOME/.ngrok-api-key
# - your ngrok authtoken in $HOME/.ngrok-authtoken
# - your ngrok domain name in $HOME/.ngrok-domain
#
# So let's make sure that those are present.

NGROK_APIKEY=$(cat $HOME/.ngrok-api-key 2>/dev/null || true)
NGROK_AUTHTOKEN=$(cat $HOME/.ngrok-authtoken 2>/dev/null || true)
NGROK_DOMAIN=$(cat $HOME/.ngrok-domain 2>/dev/null || true)

errors= ;\
if [ -z "$NGROK_APIKEY" ]; then \
  echo "You need to put your ngrok API key in $HOME/.ngrok-api-key" >&2 ;\
  errors=yes ;\
fi ;\
if [ -z "$NGROK_AUTHTOKEN" ]; then \
    echo "You need to put your ngrok authtoken in $HOME/.ngrok-authtoken" >&2 ;\
    errors=yes ;\
fi ;\
if [ -z "$NGROK_DOMAIN" ]; then \
    echo "You need to put your ngrok domain name in $HOME/.ngrok-domain" >&2 ;\
    errors=yes ;\
fi ;\
if [ -n "$errors" ]; then \
    exit 1 ;\
fi

# Make sure that we're in the namespace we expect.
kubectl ns default

# Tell demosh to show commands as they're run.
#@SHOW
#@clear

# Make sure the Linkerd CLI is up to date...
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh

# ...then install Linkerd and Linkerd viz per the quickstart. We cheat
# slightly by not running `linkerd check` before `linkerd viz` -- the viz
# installer will wait for Linkerd's control plane to be ready before
# proceeding.

linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd viz install | kubectl apply -f -
linkerd check

#@wait
#@clear

# Next up: install ngrok ingress.

kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ngrok-ingress-controller
  annotations:
    linkerd.io/inject: enabled
EOF

helm install ngrok-ingress-controller ngrok/kubernetes-ingress-controller \
  --namespace ngrok-ingress-controller \
  --set credentials.apiKey=$NGROK_APIKEY \
  --set credentials.authtoken=$NGROK_AUTHTOKEN \
  --wait

# Once that's done, install Faces, being sure to inject it into the mesh.
# Install its ServiceProfiles too: all of these things are in the k8s
# directory.

#### FACES_INSTALL_START
kubectl create ns faces
linkerd inject k8s/01-base | kubectl apply -f -
#### FACES_INSTALL_END

# Finally, configure ngrok ingress to talk to Faces.
sed -e "s,%HOSTNAME%,${NGROK_DOMAIN},g" < ngrok-ingress.yaml | kubectl apply -f -
