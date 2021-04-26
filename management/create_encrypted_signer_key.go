// create_encrypted_signer_key.sh generates encrypted JWT signer keys and
// creates the necessary KMS keyring and key.
package main

import (
	"context"
	"flag"
	"fmt"

	"github.com/m-lab/go/flagx"
	"github.com/m-lab/go/rtx"

	"github.com/stephen-soltesz/pipe/shx"
)

var (
	project string // =${1:?please provide project}
	keyid   string // =${2:?please provide keyid}
	dryrun  bool

	keyring = "soltesz-test-locate-signer"
	keyname = "soltesz-test-jwk"
)

func init() {
	flag.StringVar(&project, "project", "mlab-sandbox", "Operate on named Google Cloud Project id")
	flag.StringVar(&keyid, "keyid", "", "Key ID used as a suffix for newly created keys")
	flag.BoolVar(&dryrun, "dryrun", false, "Print a description of the commands performed")
}

func main() {
	flag.Parse()
	rtx.Must(flagx.ArgsFromEnv(flag.CommandLine), "failed to parse flags")

	locatePrivate := "jwk_sig_EdDSA_locate_" + keyid
	monitoringPrivate := "jwk_sig_EdDSA_monitoring_" + keyid

	// Create keyring if it's not already present.
	sc := shx.Script(
		shx.SetEnv("PROJECT", project),
		shx.SetEnv("KEYRING", keyring),
		shx.SetEnv("KEYNAME", keyname),
		shx.SetEnv("GCPARGS", "--project="+project),
		shx.SetEnvFromJob("keyring",
			shx.System(`gcloud ${GCPARGS} kms keyrings list \
        --location global --format='value(name)' \
        --filter "name~.*/${KEYRING}$" || :`),
		),
		shx.IfVarEmpty("keyring",
			shx.Script(
				shx.System(`echo "Creating keyring: ${KEYRING}"`),
				shx.System("gcloud ${GCPARGS} kms keyrings create ${KEYRING} --location=global"),
			),
		),
		// Create key within keyring if it's not already present.
		shx.SetEnvFromJob("key",
			shx.System(`gcloud ${GCPARGS} kms keys list \
        --location global \
        --keyring ${KEYRING} --format='value(name)' \
        --filter "name~.*/${KEYNAME}$" || :`),
		),
		shx.IfVarEmpty("key",
			shx.Script(
				shx.System(`echo "Creating key: ${KEYNAME}"`),
				shx.System(`gcloud ${GCPARGS} kms keys create ${KEYNAME} \
          --location=global \
          --keyring=${KEYRING} \
          --purpose=encryption`),
			),
		),
		// Allow AppEngine service account to access key, if it doesn't already.
		shx.SetEnvFromJob("binding",
			shx.System(`gcloud ${GCPARGS} kms keys get-iam-policy ${KEYNAME} \
			    --location global \
			    --keyring ${KEYRING} \
			    | grep serviceAccount:${PROJECT}@appspot.gserviceaccount.com || : `),
		),
		shx.IfVarEmpty("binding",
			shx.Script(
				shx.System(`echo "Binding iam policy for accessing ${KEYRING}/${KEYNAME}"`),
				shx.System(`gcloud ${GCPARGS} kms keys add-iam-policy-binding ${KEYNAME} \
			    --location=global \
			    --keyring=${KEYRING} \
			    --member=serviceAccount:${PROJECT}@appspot.gserviceaccount.com \
			    --role=roles/cloudkms.cryptoKeyDecrypter`),
			),
		),
		// Check if jwk-keygen exists.
		shx.SetEnvFromJob("JWK_KEYGEN", shx.System("which jwk-keygen || :")),
		shx.IfVarEmpty("JWK_KEYGEN",
			shx.Script(
				shx.System("echo 'ERROR: jwk-keygen not found!'"),
				shx.System("echo 'Run: go get gopkg.in/square/go-jose.v2/jwk-keygen'"),
				shx.System("exit 1"),
			),
		),
		shx.SetEnv("LOCATE_PRIVATE", locatePrivate),
		shx.SetEnv("MONITORING_PRIVATE", monitoringPrivate),
		shx.IfFileMissing(locatePrivate,
			// Create locate JWK key.
			shx.Script(
				shx.System(`echo "Creating private locate key: ${LOCATE_PRIVATE}"`),
				shx.System(`jwk-keygen --use=sig --alg=EdDSA --kid=locate_`+keyid),
			),
		),
		shx.IfFileMissing(monitoringPrivate,
			// Create monitoring JWK key.
			shx.Script(
				shx.System(`echo "Creating private monitoring key: ${MONITORING_PRIVATE}"`),
				shx.System(`jwk-keygen --use=sig --alg=EdDSA --kid=monitoring_`+keyid),
			),
		),
		shx.System(`echo "Encrypting private locate signer key:"`),
		shx.SetEnvFromJob("ENC_SIGNER_KEY",
			shx.Pipe(
				shx.ReadFile(locatePrivate),
				shx.System(`gcloud ${GCPARGS} kms encrypt --location=global \
          --plaintext-file=- --ciphertext-file=- \
          --keyring=${KEYRING} --key=${KEYNAME}`),
				shx.Exec("base64"),
			),
		),
		shx.System(`echo "Encrypting public monitoring verify key:"`),
		shx.SetEnvFromJob("ENC_VERIFY_KEY",
			shx.Pipe(
				shx.ReadFile(monitoringPrivate+".pub"),
				shx.System(`gcloud ${GCPARGS} kms encrypt --location=global \
          --plaintext-file=- --ciphertext-file=- \
          --keyring=${KEYRING} --key=${KEYNAME}`),
				shx.Exec("base64"),
			),
		),
		shx.Script(
			shx.System(`
        echo ""
        echo "Include the following in app.yaml.${PROJECT}:"
        echo ""
        echo "env_variables:"
        echo "  LOCATE_SIGNER_KEY: \"${ENC_SIGNER_KEY}\""
        echo "  MONITORING_VERIFY_KEY: \"${ENC_VERIFY_KEY}\""
      `),
		),
	)
	if dryrun {
		d := &shx.Description{}
		sc.Describe(d)
		fmt.Println(d.String())
		return
	}
	s := shx.New()
	err := sc.Run(context.Background(), s)
	if err != nil {
		fmt.Println(err)
	}
}
