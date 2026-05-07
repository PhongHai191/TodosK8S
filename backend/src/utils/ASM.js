const { SecretsManagerClient, GetSecretValueCommand } = require("@aws-sdk/client-secrets-manager");

const client = new SecretsManagerClient({
  region: "ap-southeast-2",
});

async function getSecret(secretName) {
  const command = new GetSecretValueCommand({
    SecretId: secretName,
  });

  const response = await client.send(command);

  if (response.SecretString) {
    return JSON.parse(response.SecretString);
  }

  const buff = Buffer.from(response.SecretBinary, "base64");
  return JSON.parse(buff.toString("ascii"));
}

module.exports = { getSecret };