# Render frontend

Create a Static Site from erickchoongo/zedbiz, branch pilot/free-deployment.
Root Directory: mobile
Build Command: bash ops/build_render_web.sh
Publish Directory: build/web
Auto Deploy: Off
No frontend secrets or environment variables are required by this pinned build script.

In Settings > Headers set the following on /*:
- X-Content-Type-Options: nosniff
- X-Frame-Options: DENY
- Referrer-Policy: no-referrer
- Cross-Origin-Opener-Policy: same-origin
- Cross-Origin-Embedder-Policy: require-corp
- Cache-Control: no-cache

In Redirects/Rewrites: /* -> /index.html, Rewrite.
The Cloudflare _headers file does not configure Render headers.

After Render assigns the frontend origin, append that exact HTTPS origin to the backend CORS_ORIGINS, retaining https://zedbiz-pilot.pages.dev during transition. Do not change backend TRUSTED_HOSTS or database credentials. Save and manually deploy the backend configuration. Sync pending offline operations on the old origin before switching users; browser storage does not migrate between origins.

The SDK is pinned to local verified Flutter 3.47.1 and its Git revision. Bash syntax and local Flutter release compilation have been checked; a successful remote Render build is still required. Do not infer successful deployment from a Git push.
