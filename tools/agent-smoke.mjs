#!/usr/bin/env node

const baseUrl = (process.env.TIMECAMPUS_API_BASE_URL || "http://localhost:8080/api/v1").replace(/\/$/, "")
const adminToken = process.env.TIMECAMPUS_ADMIN_TOKEN || ""
const dryRun = process.argv.includes("--dry-run")

const adminDraftPayload = {
  task: process.env.TIMECAMPUS_AGENT_TASK || "为主楼补充一版面向游客的简介",
  limit: 6,
  types: ["poi", "media", "guideline"],
  includePending: true,
}

const routePayload = {
  points: [
    { name: "主楼", lat: 39.981, lng: 116.34 },
    { name: "图书馆", lat: 39.982, lng: 116.341 },
  ],
}

function showPlan() {
  console.log("TimeCampus agent API smoke")
  console.log(`baseUrl: ${baseUrl}`)
  console.log("checks:")
  console.log("- POST /admin/agent/draft (requires TIMECAMPUS_ADMIN_TOKEN)")
  console.log("- POST /map/walking-route")
}

async function postJson(path, body, token) {
  const headers = { "Content-Type": "application/json" }
  if (token) headers.Authorization = `Bearer ${token}`
  const response = await fetch(`${baseUrl}${path}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  })
  const text = await response.text()
  let payload
  try {
    payload = text ? JSON.parse(text) : null
  } catch {
    payload = text
  }
  if (!response.ok) {
    throw new Error(`${path} returned ${response.status}: ${text}`)
  }
  return payload
}

function unwrapData(payload, path) {
  if (!payload || typeof payload !== "object") {
    throw new Error(`${path} returned an empty response`)
  }
  if ("code" in payload && payload.code !== 0) {
    throw new Error(`${path} returned code=${payload.code}: ${payload.message || ""}`)
  }
  return "data" in payload ? payload.data : payload
}

function assertDraft(data) {
  if (!data?.draft || !data?.contextPack?.retrieval || !data?.quality) {
    throw new Error("/admin/agent/draft missing draft, contextPack or quality")
  }
  if (!data.qualityGate || typeof data.qualityGate.executable !== "boolean") {
    throw new Error("/admin/agent/draft missing structured qualityGate")
  }
  console.log(
    `admin draft ok: mode=${data.mode}, overall=${data.quality.overall}, executable=${data.qualityGate.executable}`
  )
}

function assertRoute(data) {
  if (!Array.isArray(data?.legs) || data.legs.length !== 1) {
    throw new Error("/map/walking-route should return one leg for two points")
  }
  if (typeof data.totalDistanceMeters !== "number" || typeof data.totalDurationSeconds !== "number") {
    throw new Error("/map/walking-route missing total distance or duration")
  }
  console.log(
    `walking route ok: distance=${data.totalDistanceMeters}m, duration=${data.totalDurationSeconds}s`
  )
}

async function main() {
  showPlan()
  if (dryRun) {
    console.log("dry-run: no requests sent")
    console.log(JSON.stringify({ adminDraftPayload, routePayload }, null, 2))
    return
  }

  if (adminToken) {
    const draft = unwrapData(await postJson("/admin/agent/draft", adminDraftPayload, adminToken), "/admin/agent/draft")
    assertDraft(draft)
  } else {
    console.log("skip admin draft: set TIMECAMPUS_ADMIN_TOKEN to enable it")
  }

  const route = unwrapData(await postJson("/map/walking-route", routePayload), "/map/walking-route")
  assertRoute(route)
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error)
  process.exitCode = 1
})
