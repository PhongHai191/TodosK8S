const {
  S3Client,
  PutObjectCommand,
  GetObjectCommand
} = require("@aws-sdk/client-s3");

const { getSignedUrl } = require("@aws-sdk/s3-request-presigner");

// init S3
const s3 = new S3Client({
  region: process.env.AWS_REGION
});

const BUCKET = process.env.AWS_S3_BUCKET;


// =======================
// 🟢 1. Tạo URL upload
// =======================
async function getUploadUrl(filename, type) {
  const key = `avatars/${Date.now()}-${filename}`;

  const command = new PutObjectCommand({
    Bucket: BUCKET,
    Key: key,
    ContentType: type
  });

  const uploadUrl = await getSignedUrl(s3, command, {
    expiresIn: 60 
  });

  return {
    uploadUrl,
    key 
  };
}

async function getAvatarUrl(key) {
  if (!key) return null;

  const command = new GetObjectCommand({
    Bucket: BUCKET,
    Key: key
  });

  const signedUrl = await getSignedUrl(s3, command, {
    expiresIn: 3600 
  });

  return signedUrl;
}


module.exports = {
  getUploadUrl,
  getAvatarUrl
};