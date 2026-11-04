// Спільні функції: виклик RPC Supabase через REST, без бібліотек.
window.rpc = async function (fn, args) {
  const c = window.EDKI_CONFIG;
  const r = await fetch(`${c.SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: c.SUPABASE_ANON_KEY,
      Authorization: `Bearer ${c.SUPABASE_ANON_KEY}`,
    },
    body: JSON.stringify(args || {}),
  });
  const text = await r.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch (e) { data = text; }
  if (!r.ok) throw new Error((data && data.message) || `Помилка сервера (${r.status})`);
  return data;
};

window.store = {
  get(k) { try { return JSON.parse(localStorage.getItem(k)); } catch (e) { return null; } },
  set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} },
  del(k) { try { localStorage.removeItem(k); } catch (e) {} },
};

window.esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
