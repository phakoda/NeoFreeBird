# NeoFreeBird Webhook Server

A lightweight Express.js server that posts tweets via Twitter API v2 on behalf of the NeoFreeBird iOS client. This bypasses X's attestation checks on modified clients.

## Prerequisites

- Node.js 18+
- Twitter API v2 credentials (Free tier works for posting)

## Setup

1. **Get Twitter API credentials:**
   - Go to [developer.twitter.com](https://developer.twitter.com/en/portal/dashboard)
   - Create a project and app
   - Generate API Key, API Secret, Access Token, and Access Secret
   - Ensure your app has **Read and Write** permissions

2. **Configure the server:**
   ```bash
   cp .env.example .env
   # Edit .env with your Twitter credentials
   ```

3. **Install and run:**
   ```bash
   npm install
   npm start
   ```

4. **Configure NeoFreeBird:**
   - Go to NeoFreeBird Settings → Web API Tweeting
   - Enable "Web API Tweeting"
   - Set Webhook URL to `http://your-server-ip:3000`
   - Set API Key to match the `API_KEY` in your `.env` file
   - Tap "Test Connection" to verify

## Deployment Options

### Local Network (Simplest)
Run on a machine on your local network and point the app to `http://local-ip:3000`.

### Cloud (Recommended for always-on)
Deploy to any cloud provider:
- **Railway**: `railway up`
- **Render**: Connect repo, set env vars
- **DigitalOcean**: Use App Platform
- **VPS**: Run with pm2: `pm2 start server.js`

> **Note**: If deploying publicly, always set a strong `API_KEY` in `.env`.

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check |
| POST | `/tweet` | Post a tweet |

### POST /tweet

```json
{
  "text": "Hello from NeoFreeBird!",
  "reply_to_id": "optional_tweet_id",
  "quote_tweet_id": "optional_tweet_id",
  "media": [
    {
      "data": "base64_encoded_image_data",
      "mime_type": "image/jpeg"
    }
  ]
}
```

### Response

```json
{
  "success": true,
  "tweet_id": "1234567890",
  "message": "Tweet posted successfully!"
}
```
