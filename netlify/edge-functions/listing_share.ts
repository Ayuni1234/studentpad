import type { Context } from "@netlify/edge-functions";

type Listing = {
  id: string;
  title: string;
  description: string | null;
  listing_type: string;
  location: string;
  monthly_rent_ghs: number;
  image_path: string | null;
  images: string[] | null;
};

const crawlerPattern =
  /bot|crawler|spider|facebookexternalhit|whatsapp|twitterbot|linkedinbot|slackbot|discordbot|telegrambot|pinterest/i;

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (character) => {
    const entities: Record<string, string> = {
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    };
    return entities[character];
  });
}

function photoUrl(supabaseUrl: string, path: string): string {
  const encodedPath = path.split("/").map(encodeURIComponent).join("/");
  return `${supabaseUrl.replace(/\/$/, "")}/storage/v1/object/public/listing-photos/${encodedPath}`;
}

function previewHtml(listing: Listing, canonicalUrl: string, imageUrl: string | null): string {
  const title = `${listing.title} · GHS ${Number(listing.monthly_rent_ghs).toLocaleString("en-GH")} / month | StudentPad`;
  const description = [listing.location, listing.description?.trim()]
    .filter((part): part is string => Boolean(part))
    .join(" · ")
    .slice(0, 240);
  const imageTags = imageUrl
    ? `<meta property="og:image" content="${escapeHtml(imageUrl)}">
    <meta property="og:image:alt" content="${escapeHtml(listing.title)}">
    <meta name="twitter:card" content="summary_large_image">`
    : `<meta name="twitter:card" content="summary">`;

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(title)}</title>
  <meta name="description" content="${escapeHtml(description)}">
  <link rel="canonical" href="${escapeHtml(canonicalUrl)}">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="StudentPad">
  <meta property="og:title" content="${escapeHtml(title)}">
  <meta property="og:description" content="${escapeHtml(description)}">
  <meta property="og:url" content="${escapeHtml(canonicalUrl)}">
  ${imageTags}
  <meta name="twitter:title" content="${escapeHtml(title)}">
  <meta name="twitter:description" content="${escapeHtml(description)}">
</head>
<body>
  <p><a href="${escapeHtml(canonicalUrl)}">${escapeHtml(listing.title)} · ${escapeHtml(listing.location)} · GHS ${Number(listing.monthly_rent_ghs).toLocaleString("en-GH")} / month</a></p>
</body>
</html>`;
}

export default async (request: Request, context: Context) => {
  const userAgent = request.headers.get("user-agent") ?? "";
  if (!crawlerPattern.test(userAgent)) return context.next();

  const pathMatch = new URL(request.url).pathname.match(
    /^\/listing\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\/?$/i,
  );
  if (!pathMatch) return context.next();

  const supabaseUrl = Netlify.env.get("SUPABASE_URL");
  const anonKey = Netlify.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) return context.next();

  const apiUrl = new URL(`${supabaseUrl.replace(/\/$/, "")}/rest/v1/listings`);
  apiUrl.searchParams.set("id", `eq.${pathMatch[1]}`);
  apiUrl.searchParams.set("is_active", "eq.true");
  apiUrl.searchParams.set(
    "select",
    "id,title,description,listing_type,location,monthly_rent_ghs,image_path,images",
  );
  apiUrl.searchParams.set("limit", "1");

  try {
    const response = await fetch(apiUrl, {
      headers: {
        apikey: anonKey,
        Authorization: `Bearer ${anonKey}`,
      },
    });
    if (!response.ok) return context.next();
    const listings = (await response.json()) as Listing[];
    const listing = listings[0];
    if (!listing) return context.next();

    const siteOrigin =
      Netlify.env.get("STUDENTPAD_PUBLIC_WEB_ORIGIN") ?? context.site.url;
    const canonicalUrl = new URL(`/listing/${listing.id}`, siteOrigin).toString();
    const images = Array.isArray(listing.images) ? listing.images : [];
    const primaryImage = images.find((path) => typeof path === "string" && path.length > 0)
      ?? listing.image_path;
    const html = previewHtml(
      listing,
      canonicalUrl,
      primaryImage ? photoUrl(supabaseUrl, primaryImage) : null,
    );

    return new Response(html, {
      headers: {
        "content-type": "text/html; charset=utf-8",
        "cache-control": "public, max-age=300, s-maxage=300, stale-while-revalidate=3600",
        "x-content-type-options": "nosniff",
      },
    });
  } catch {
    return context.next();
  }
};
