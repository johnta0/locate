 1: (
 2:   export PROJECT="mlab-sandbox"
 3:   export KEYRING="soltesz-test-locate-signer"
 4:   export KEYNAME="soltesz-test-jwk"
 5:   export GCPARGS="--project=mlab-sandbox"
 6:   export LOCATE_PRIVATE="jwk_sig_EdDSA_locate_"
 7:   export MONITORING_PRIVATE="jwk_sig_EdDSA_monitoring_"
 8:   export keyring=$(/bin/sh -c gcloud ${GCPARGS} kms keyrings list \
				--location global --format='value(name)' \
				--filter "name~.*/${KEYRING}$" || :)
 9:   if [[ -z ${keyring} ]] ; then
10:     (
11:       echo "Creating keyring: ${KEYRING}"
12:       /bin/sh -c gcloud ${GCPARGS} kms keyrings create ${KEYRING} --location=global
13:     )
14:   fi
15:   export key=$(/bin/sh -c gcloud ${GCPARGS} kms keys list \
			--location global \
			--keyring ${KEYRING} --format='value(name)' \
			--filter "name~.*/${KEYNAME}$" || :)
16:   if [[ -z ${key} ]] ; then
17:     (
18:       echo "Creating key: ${KEYNAME}"
19:       /bin/sh -c gcloud ${GCPARGS} kms keys create ${KEYNAME} \
					--location=global \
					--keyring=${KEYRING} \
					--purpose=encryption
20:     )
21:   fi
22:   export binding=$(/bin/sh -c gcloud ${GCPARGS} kms keys get-iam-policy ${KEYNAME} \
					--location global \
					--keyring ${KEYRING} || :
				 | /bin/sh -c grep serviceAccount:${PROJECT}@appspot.gserviceaccount.com)
23:   if [[ -z ${binding} ]] ; then
24:     (
25:       echo "Binding iam policy for accessing ${KEYRING}/${KEYNAME}"
26:       /bin/sh -c gcloud ${GCPARGS} kms keys add-iam-policy-binding ${KEYNAME} \
					--location=global \
					--keyring=${KEYRING} \
					--member=serviceAccount:${PROJECT}@appspot.gserviceaccount.com \
					--role=roles/cloudkms.cryptoKeyDecrypter
27:     )
28:   fi
29:   export JWK_KEYGEN=$(/bin/sh -c which jwk-keygen || :)
30:   if [[ -z ${JWK_KEYGEN} ]] ; then
31:     (
32:       echo "ERROR: jwk-keygen not found!"
33:       echo "FIX by running: go get gopkg.in/square/go-jose.v2/jwk-keygen"
34:       /bin/sh -c exit 1
35:     )
36:   fi
37:   if [[ ! -f jwk_sig_EdDSA_locate_ ]] ; then
38:     (
39:       echo "Creating private locate key: ${LOCATE_PRIVATE}"
40:       /bin/sh -c jwk-keygen --use=sig --alg=EdDSA --kid=locate_
41:     )
42:   fi
43:   if [[ ! -f jwk_sig_EdDSA_monitoring_ ]] ; then
44:     (
45:       echo "Creating private monitoring key: ${MONITORING_PRIVATE}"
46:       /bin/sh -c jwk-keygen --use=sig --alg=EdDSA --kid=monitoring_
47:     )
48:   fi
49:   echo "Encrypting private locate signer key:"
50:   export ENC_SIGNER_KEY=$(cat < jwk_sig_EdDSA_locate_ | /bin/sh -c gcloud ${GCPARGS} kms encrypt --location=global \
					--plaintext-file=- --ciphertext-file=- \
					--keyring=${KEYRING} --key=${KEYNAME} | base64)
51:   echo "Encrypting public monitoring verify key:"
52:   export ENC_VERIFY_KEY=$(cat < jwk_sig_EdDSA_monitoring_.pub | /bin/sh -c gcloud ${GCPARGS} kms encrypt --location=global \
					--plaintext-file=- --ciphertext-file=- \
					--keyring=${KEYRING} --key=${KEYNAME} | base64)
53:   (
54:     echo "Include the following in app.yaml.${PROJECT}:"
55:     echo "env_variables:"
56:     echo "  LOCATE_SIGNER_KEY: \"${ENC_SIGNER_KEY}\""
57:     echo "  MONITORING_VERIFY_KEY: \"${ENC_VERIFY_KEY}\""
58:   )
59: )

