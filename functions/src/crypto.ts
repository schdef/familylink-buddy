import * as crypto from "crypto";

const ALGORITHM = "aes-256-gcm";
const IV_LENGTH = 12; // 96 bits for GCM
const SALT_LENGTH = 16;
const KEY_LENGTH = 32;

// In production, load the secret key from GCP Secret Manager.
// For local testing, we fallback to a developer default key.
function getEncryptionKey(): Buffer {
  const secret = process.env.TOKEN_ENCRYPTION_SECRET || "dev-default-familylink-buddy-secret-key-32-bytes";
  // Derives a 32-byte key from the secret
  return crypto.scryptSync(secret, "salt-familylink", KEY_LENGTH);
}

export function encrypt(text: string): string {
  const iv = crypto.randomBytes(IV_LENGTH);
  const salt = crypto.randomBytes(SALT_LENGTH);
  const key = getEncryptionKey();

  const cipher = crypto.createCipheriv(ALGORITHM, key, iv);
  
  let encrypted = cipher.update(text, "utf8", "hex");
  encrypted += cipher.final("hex");
  
  const authTag = cipher.getAuthTag().toString("hex");

  // Output format: iv:salt:authTag:ciphertext
  return `${iv.toString("hex")}:${salt.toString("hex")}:${authTag}:${encrypted}`;
}

export function decrypt(ciphertextWithMetadata: string): string {
  const parts = ciphertextWithMetadata.split(":");
  if (parts.length !== 4) {
    throw new Error("Invalid encrypted text format");
  }

  const iv = Buffer.from(parts[0], "hex");
  // Salt could be used for dynamic scrypt but for simple AES-GCM we use static derivation
  const authTag = Buffer.from(parts[2], "hex");
  const encryptedText = parts[3];
  const key = getEncryptionKey();

  const decipher = crypto.createDecipheriv(ALGORITHM, key, iv);
  decipher.setAuthTag(authTag);

  let decrypted = decipher.update(encryptedText, "hex", "utf8");
  decrypted += decipher.final("utf8");

  return decrypted;
}
