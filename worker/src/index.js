const repository = 'gentoobreaking/guoapp';
const platforms = new Set(['android', 'ios', 'windows', 'darwin', 'linux']);
const builds = new Set(['guoapp', 'hongguojian', 'zhenguojian']);

// /v1/ping 簡易速率限制：每 IP 每分鐘最多 10 次（正常使用每裝置每天僅上報一次）
const pingRate = new Map();
const PING_LIMIT = 10;
const PING_WINDOW_MS = 60 * 1000;

const pingAllowed = (ip) => {
  const now = Date.now();
  const entry = pingRate.get(ip) || { count: 0, reset: now + PING_WINDOW_MS };
  if (now > entry.reset) {
    pingRate.set(ip, { count: 1, reset: now + PING_WINDOW_MS });
    return true;
  }
  if (entry.count >= PING_LIMIT) return false;
  entry.count += 1;
  pingRate.set(ip, entry);
  return true;
};

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });

const beijingDay = () =>
  new Date(Date.now() + 8 * 3600 * 1000).toISOString().slice(0, 10);

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'GET' && url.pathname === '/v1/latest') {
      const latest = await env.DB.prepare(
        "SELECT value FROM meta WHERE key = 'latest'",
      ).first('value');
      return json(latest ? JSON.parse(latest) : {});
    }
    if (request.method !== 'POST' || url.pathname !== '/v1/ping') {
      return new Response('Not Found', { status: 404 });
    }

    // 速率限制
    const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
    if (!pingAllowed(ip)) {
      return json({ error: 'rate limited' }, 429);
    }

    // 可選的 Bearer Token 鑑權（設定 PING_TOKEN 時啟用）
    const pingToken = env.PING_TOKEN;
    if (pingToken) {
      const auth = request.headers.get('Authorization') ?? '';
      if (!auth.startsWith('Bearer ') || auth.slice(7) !== pingToken) {
        return json({ error: 'unauthorized' }, 401);
      }
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: 'invalid' }, 400);
    }
    const { id, version, platform, build } = body ?? {};
    if (
      !/^[0-9a-f]{32}$/.test(id) ||
      !/^\d+\.\d+\.\d+\+\d+$/.test(version) ||
      !platforms.has(platform) ||
      !builds.has(build)
    ) {
      return json({ error: 'invalid' }, 400);
    }
    await env.DB.prepare(
      `INSERT INTO pings (day, id, version, platform, build) VALUES (?1, ?2, ?3, ?4, ?5)
       ON CONFLICT (day, id) DO UPDATE SET version = excluded.version, platform = excluded.platform, build = excluded.build`,
    )
      .bind(beijingDay(), id, version, platform, build)
      .run();
    return new Response(null, { status: 204 });
  },

  async scheduled(_, env) {
    try {
      const response = await fetch(
        `https://api.github.com/repos/${repository}/releases/latest`,
        {
          headers: {
            Accept: 'application/vnd.github+json',
            'User-Agent': 'videoapp-update',
          },
        },
      );
      if (!response.ok) return;
      const release = await response.json();
      const match = /^app-v(\d+\.\d+\.\d+)-(\d+)$/.exec(release.tag_name ?? '');
      if (!match) return;
      const latest = { version: `${match[1]}+${match[2]}`, url: release.html_url };
      await env.DB.prepare(
        "INSERT INTO meta (key, value) VALUES ('latest', ?1) ON CONFLICT (key) DO UPDATE SET value = excluded.value",
      )
        .bind(JSON.stringify(latest))
        .run();
    } catch (err) {
      console.error('[scheduled] failed to fetch latest release:', err);
    }
  },
};
