 1: (
 2:   export PROJECT="mlab-sandbox"
 3:   export KEYRING="soltesz-test-locate-signer"
 4:   export KEYNAME="soltesz-test-jwk"
 5:   export GCPARGS="--project=mlab-sandbox"
 6:   export keyring=$(/bin/sh -c gcloud ${GCPARGS} kms keyrings list \
				--location global --format='value(name)' \
				--filter "name~.*/${KEYRING}$" || :)
 7:   if [[ -z ${keyring} ]] ; then
 8:     (
 9:       /bin/sh -c echo "Creating keyring: ${KEYRING}"
10:       /bin/sh -c gcloud ${GCPARGS} kms keyrings create ${KEYRING} --location=global
11:     )
12:   fi
13:   export key=$(/bin/sh -c gcloud ${GCPARGS} kms keys list \
			--location global \
			--keyring ${KEYRING} --format='value(name)' \
			--filter "name~.*/${KEYNAME}$" || :)
14:   if [[ -z ${key} ]] ; then
15:     (
16:       /bin/sh -c echo "Creating key: ${KEYNAME}"
17:       /bin/sh -c gcloud ${GCPARGS} kms keys create ${KEYNAME} \
					--location=global \
					--keyring=${KEYRING} \
					--purpose=encryption
18:     )
19:   fi
20:   export binding=$(/bin/sh -c gcloud ${GCPARGS} kms keys get-iam-policy ${KEYNAME} \
					--location global \
					--keyring ${KEYRING} \
					| grep serviceAccount:${PROJECT}@appspot.gserviceaccount.com || : )
21:   if [[ -z ${binding} ]] ; then
22:     (
23:       /bin/sh -c echo "Binding iam policy for accessing ${KEYRING}/${KEYNAME}"
24:       /bin/sh -c gcloud ${GCPARGS} kms keys add-iam-policy-binding ${KEYNAME} \
					--location=global \
					--keyring=${KEYRING} \
					--member=serviceAccount:${PROJECT}@appspot.gserviceaccount.com \
					--role=roles/cloudkms.cryptoKeyDecrypter
25:     )
26:   fi
27:   export JWK_KEYGEN=$(/bin/sh -c which jwk-keygen || :)
28:   if [[ -z ${JWK_KEYGEN} ]] ; then
29:     (
30:       /bin/sh -c echo 'ERROR: jwk-keygen not found!'
31:       /bin/sh -c echo 'Run: go get gopkg.in/square/go-jose.v2/jwk-keygen'
32:       /bin/sh -c exit 1
33:     )
34:   fi
35:   export LOCATE_PRIVATE="jwk_sig_EdDSA_locate_"
36:   export MONITORING_PRIVATE="jwk_sig_EdDSA_monitoring_"
37:   if [[ ! -f jwk_sig_EdDSA_locate_ ]] ; then
38:     (
39:       /bin/sh -c echo "Creating private locate key: ${LOCATE_PRIVATE}"
40:       /bin/sh -c jwk-keygen --use=sig --alg=EdDSA --kid=locate_
41:     )
42:   fi
43:   if [[ ! -f jwk_sig_EdDSA_monitoring_ ]] ; then
44:     (
45:       /bin/sh -c echo "Creating private monitoring key: ${MONITORING_PRIVATE}"
46:       /bin/sh -c jwk-keygen --use=sig --alg=EdDSA --kid=monitoring_
47:     )
48:   fi
49:   /bin/sh -c echo "Encrypting private locate signer key:"
50:   export ENC_SIGNER_KEY=$(cat < jwk_sig_EdDSA_locate_ | /bin/sh -c gcloud ${GCPARGS} kms encrypt --location=global \
					--plaintext-file=- --ciphertext-file=- \
					--keyring=${KEYRING} --key=${KEYNAME} | base64)
51:   /bin/sh -c echo "Encrypting public monitoring verify key:"
52:   export ENC_VERIFY_KEY=$(cat < jwk_sig_EdDSA_monitoring_.pub | /bin/sh -c gcloud ${GCPARGS} kms encrypt --location=global \
					--plaintext-file=- --ciphertext-file=- \
					--keyring=${KEYRING} --key=${KEYNAME} | base64)
53:   (
54:     /bin/sh -c 
				echo ""
				echo "Include the following in app.yaml.${PROJECT}:"
				echo ""
				echo "env_variables:"
				echo "  LOCATE_SIGNER_KEY: \"${ENC_SIGNER_KEY}\""
				echo "  MONITORING_VERIFY_KEY: \"${ENC_VERIFY_KEY}\""
55:   )
56: )

