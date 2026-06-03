import React, { useState, useMemo } from "react";
import {
  ChevronLeft, ChevronRight, Search, Plus, Check, X,
  Store, Phone, Trash2, Pencil, CheckCircle2, Clock, ArrowDown,
} from "lucide-react";

/* ──────────────────────────────────────────────────────────────
   Shutter Ledger — glassmorphic monthly rent tracker
   Single-file React UI. State only (no persistence).
   ────────────────────────────────────────────────────────────── */

const BS_MONTHS = [
  "Baishakh", "Jestha", "Ashadh", "Shrawan", "Bhadra", "Ashwin",
  "Kartik", "Mangsir", "Poush", "Magh", "Falgun", "Chaitra",
];

const seedShutters = [
  { id: 1, no: "A-01", tenant: "Rajesh Shrestha", biz: "Tea & Snacks", rent: 18000, phone: "9801234501" },
  { id: 2, no: "A-02", tenant: "Anjali Thapa", biz: "Tailoring", rent: 15000, phone: "9801234502" },
  { id: 3, no: "A-03", tenant: "Bikash Gurung", biz: "Mobile Repair", rent: 22000, phone: "9801234503" },
  { id: 4, no: "A-04", tenant: "Sita Magar", biz: "Beauty Parlour", rent: 20000, phone: "9801234504" },
  { id: 5, no: "B-01", tenant: "Hari Adhikari", biz: "Stationery", rent: 16000, phone: "9801234505" },
  { id: 6, no: "B-02", tenant: "Maya Tamang", biz: "Grocery", rent: 25000, phone: "9801234506" },
  { id: 7, no: "B-03", tenant: "Deepak Rai", biz: "Hardware", rent: 28000, phone: "9801234507" },
  { id: 8, no: "B-04", tenant: "Sunita K.C.", biz: "Clothing", rent: 24000, phone: "9801234508" },
  { id: 9, no: "C-01", tenant: "Ramesh Poudel", biz: "Pharmacy", rent: 30000, phone: "9801234509" },
  { id: 10, no: "C-02", tenant: "Gita Bhandari", biz: "Bakery", rent: 19000, phone: "9801234510" },
];

const today = new Date();
const startYear = 2082;
const startMonth = 1; // Jestha

const seedPayments = {
  [`${startYear}-1`]: {
    1: { paid: true, date: "Jestha 3" },
    2: { paid: true, date: "Jestha 5" },
    5: { paid: true, date: "Jestha 2" },
    6: { paid: true, date: "Jestha 8" },
    9: { paid: true, date: "Jestha 1" },
    10: { paid: true, date: "Jestha 6" },
  },
  [`${startYear}-0`]: Object.fromEntries(
    seedShutters.map((s) => [s.id, { paid: true, date: "Baishakh" }])
  ),
};

const npr = (n) => "Rs " + n.toLocaleString("en-IN");

export default function ShutterLedger() {
  const [shutters, setShutters] = useState(seedShutters);
  const [payments, setPayments] = useState(seedPayments);
  const [year, setYear] = useState(startYear);
  const [month, setMonth] = useState(startMonth);
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState("all");
  const [sheet, setSheet] = useState(null);
  const [form, setForm] = useState(null);

  const monthKey = `${year}-${month}`;
  const monthPay = payments[monthKey] || {};
  const isPaid = (id) => !!monthPay[id]?.paid;

  const togglePaid = (id) => {
    setPayments((prev) => {
      const m = { ...(prev[monthKey] || {}) };
      if (m[id]?.paid) delete m[id];
      else m[id] = { paid: true, date: `${BS_MONTHS[month]} ${today.getDate()}` };
      return { ...prev, [monthKey]: m };
    });
  };

  const stepMonth = (dir) => {
    let m = month + dir, y = year;
    if (m < 0) { m = 11; y -= 1; }
    if (m > 11) { m = 0; y += 1; }
    setMonth(m); setYear(y);
  };

  const stats = useMemo(() => {
    const expected = shutters.reduce((a, s) => a + s.rent, 0);
    const collected = shutters.reduce((a, s) => a + (isPaid(s.id) ? s.rent : 0), 0);
    const paidCount = shutters.filter((s) => isPaid(s.id)).length;
    return { expected, collected, pending: expected - collected, paidCount, total: shutters.length };
  }, [shutters, monthPay]);

  const list = useMemo(() => {
    return shutters
      .filter((s) => {
        const q = query.trim().toLowerCase();
        const match = !q ||
          s.tenant.toLowerCase().includes(q) ||
          s.no.toLowerCase().includes(q) ||
          s.biz.toLowerCase().includes(q);
        const f = filter === "all" || (filter === "paid" ? isPaid(s.id) : !isPaid(s.id));
        return match && f;
      })
      .sort((a, b) => Number(isPaid(a.id)) - Number(isPaid(b.id)));
  }, [shutters, query, filter, monthPay]);

  const saveForm = () => {
    if (!form.no?.trim() || !form.tenant?.trim()) return;
    const rent = parseInt(form.rent, 10) || 0;
    if (form.id) {
      setShutters((p) => p.map((s) => (s.id === form.id ? { ...s, ...form, rent } : s)));
      setSheet((s) => (s && s.id === form.id ? { ...s, ...form, rent } : s));
    } else {
      const id = Math.max(0, ...shutters.map((s) => s.id)) + 1;
      setShutters((p) => [...p, { ...form, id, rent }]);
    }
    setForm(null);
  };

  const removeShutter = (id) => {
    setShutters((p) => p.filter((s) => s.id !== id));
    setSheet(null);
  };

  const pct = stats.expected ? Math.round((stats.collected / stats.expected) * 100) : 0;

  return (
    <div style={S.root}>
      <style>{CSS}</style>

      <div style={S.phone}>
        {/* colored light field behind the glass */}
        <div style={S.bg}>
          <div style={{ ...S.orb, ...S.orbA }} />
          <div style={{ ...S.orb, ...S.orbB }} />
          <div style={{ ...S.orb, ...S.orbC }} />
          <div style={{ ...S.orb, ...S.orbD }} />
          <div style={S.grain} />
        </div>

        <div style={S.scroll}>
          {/* Header */}
          <header style={S.header}>
            <div style={S.brandRow}>
              <div style={S.brandMark}><Store size={15} strokeWidth={2.2} /></div>
              <span style={S.brand}>Shutter Ledger</span>
            </div>
            <div style={{ ...S.glass, ...S.monthNav }}>
              <button style={S.navBtn} onClick={() => stepMonth(-1)} aria-label="prev"><ChevronLeft size={18} /></button>
              <div style={S.monthLabel}>
                <span style={S.monthName}>{BS_MONTHS[month]}</span>
                <span style={S.monthYear}>{year}</span>
              </div>
              <button style={S.navBtn} onClick={() => stepMonth(1)} aria-label="next"><ChevronRight size={18} /></button>
            </div>
          </header>

          {/* Summary */}
          <section style={{ ...S.glass, ...S.summary }}>
            <div style={S.sheen} />
            <div style={S.sumTop}>
              <span style={S.sumLabel}>Collected this month</span>
              <span style={S.sumPct}>{pct}%</span>
            </div>
            <div style={S.bigNum}>{npr(stats.collected)}</div>
            <div style={S.ofExpected}>of {npr(stats.expected)} expected</div>
            <div style={S.bar}><div style={{ ...S.barFill, width: `${pct}%` }} /></div>
            <div style={S.sumStats}>
              <div style={S.statChip}>
                <CheckCircle2 size={14} style={{ color: "#4ee0a8" }} />
                <span><b>{stats.paidCount}</b>/{stats.total} paid</span>
              </div>
              <div style={S.statChip}>
                <Clock size={14} style={{ color: "#ff8a3d" }} />
                <span><b>{npr(stats.pending)}</b> pending</span>
              </div>
            </div>
          </section>

          {/* Search + filters */}
          <div style={S.controls}>
            <div style={{ ...S.glass, ...S.searchWrap }}>
              <Search size={16} style={{ color: "var(--muted)" }} />
              <input style={S.search} placeholder="Search tenant or shutter…"
                value={query} onChange={(e) => setQuery(e.target.value)} />
              {query && <X size={15} style={{ color: "var(--muted)", cursor: "pointer" }} onClick={() => setQuery("")} />}
            </div>
            <div style={S.chips}>
              {[["all", "All"], ["pending", "Pending"], ["paid", "Paid"]].map(([k, label]) => (
                <button key={k} onClick={() => setFilter(k)}
                  style={{ ...S.glass, ...S.chip, ...(filter === k ? S.chipOn : {}) }}>{label}</button>
              ))}
            </div>
          </div>

          {/* List */}
          <div style={S.list}>
            {list.length === 0 && <div style={S.empty}>No shutters match.</div>}
            {list.map((s) => {
              const paid = isPaid(s.id);
              return (
                <div key={s.id} style={{ ...S.glass, ...S.row }} onClick={() => setSheet(s)} className="row">
                  <div style={{ ...S.avatar, background: paid ? "rgba(52,211,153,.18)" : "rgba(255,255,255,.08)", borderColor: paid ? "rgba(52,211,153,.45)" : "rgba(255,255,255,.16)" }}>
                    <span style={{ ...S.avatarTxt, color: paid ? "#4ee0a8" : "#fff" }}>{s.no}</span>
                  </div>
                  <div style={S.rowMid}>
                    <div style={S.tenant}>{s.tenant}</div>
                    <div style={S.biz}>{s.biz}</div>
                  </div>
                  <div style={S.rowRight}>
                    <div style={S.rent}>{npr(s.rent)}</div>
                    <button className="pill"
                      onClick={(e) => { e.stopPropagation(); togglePaid(s.id); }}
                      style={{ ...S.pill, ...(paid ? S.pillPaid : S.pillDue) }}>
                      {paid ? <><Check size={12} strokeWidth={3} /> Paid</> : "Mark paid"}
                    </button>
                  </div>
                </div>
              );
            })}
            <div style={{ height: 96 }} />
          </div>
        </div>

        {/* FAB */}
        <button style={S.fab} className="fab"
          onClick={() => setForm({ no: "", tenant: "", biz: "", rent: "", phone: "" })}>
          <Plus size={24} strokeWidth={2.4} />
        </button>

        {/* Detail sheet */}
        {sheet && (
          <Sheet onClose={() => setSheet(null)}>
            <div style={S.sheetHead}>
              <div style={{ ...S.avatar, width: 52, height: 52, background: "rgba(52,211,153,.18)", borderColor: "rgba(52,211,153,.45)" }}>
                <span style={{ ...S.avatarTxt, color: "#4ee0a8", fontSize: 15 }}>{sheet.no}</span>
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ ...S.tenant, fontSize: 18 }}>{sheet.tenant}</div>
                <div style={S.biz}>{sheet.biz}</div>
              </div>
              <button style={{ ...S.glass, ...S.iconBtn }} onClick={() => setForm({ ...sheet })}><Pencil size={16} /></button>
              <button style={{ ...S.glass, ...S.iconBtn }} onClick={() => removeShutter(sheet.id)}><Trash2 size={16} /></button>
            </div>

            <div style={S.detailGrid}>
              <div style={{ ...S.glass, ...S.detailCell }}>
                <span style={S.detailLabel}>Monthly rent</span>
                <span style={S.detailVal}>{npr(sheet.rent)}</span>
              </div>
              <div style={{ ...S.glass, ...S.detailCell }}>
                <span style={S.detailLabel}>Contact</span>
                <span style={{ ...S.detailVal, fontSize: 15, display: "flex", alignItems: "center", gap: 5 }}>
                  <Phone size={13} /> {sheet.phone || "—"}
                </span>
              </div>
            </div>

            <button onClick={() => togglePaid(sheet.id)}
              style={{ ...S.bigBtn, ...(isPaid(sheet.id) ? S.bigBtnUndo : S.bigBtnPay) }}>
              {isPaid(sheet.id)
                ? <>Paid on {monthPay[sheet.id]?.date} · tap to undo</>
                : <><ArrowDown size={17} strokeWidth={2.4} /> Collect {npr(sheet.rent)} for {BS_MONTHS[month]}</>}
            </button>

            <div style={S.histLabel}>Recent months</div>
            <div style={S.histStrip}>
              {Array.from({ length: 6 }).map((_, i) => {
                let m = month - i, y = year;
                while (m < 0) { m += 12; y -= 1; }
                const p = payments[`${y}-${m}`]?.[sheet.id]?.paid;
                return (
                  <div key={i} style={S.histCell}>
                    <div style={{ ...S.histDot, background: p ? "rgba(52,211,153,.95)" : "rgba(255,255,255,.07)", color: p ? "#053026" : "var(--muted)", borderColor: p ? "transparent" : "rgba(255,255,255,.16)" }}>
                      {p ? <Check size={13} strokeWidth={3} /> : "–"}
                    </div>
                    <span style={S.histM}>{BS_MONTHS[m].slice(0, 3)}</span>
                  </div>
                );
              }).reverse()}
            </div>
          </Sheet>
        )}

        {/* Add / Edit form */}
        {form && (
          <Sheet onClose={() => setForm(null)}>
            <div style={S.formTitle}>{form.id ? "Edit shutter" : "New shutter"}</div>
            <Field label="Shutter no." value={form.no} onChange={(v) => setForm({ ...form, no: v })} placeholder="A-05" />
            <Field label="Tenant name" value={form.tenant} onChange={(v) => setForm({ ...form, tenant: v })} placeholder="Full name" />
            <Field label="Business" value={form.biz} onChange={(v) => setForm({ ...form, biz: v })} placeholder="e.g. Grocery" />
            <div style={{ display: "flex", gap: 10 }}>
              <Field label="Rent (Rs)" value={form.rent} onChange={(v) => setForm({ ...form, rent: v.replace(/\D/g, "") })} placeholder="18000" flex />
              <Field label="Phone" value={form.phone} onChange={(v) => setForm({ ...form, phone: v })} placeholder="98…" flex />
            </div>
            <button style={{ ...S.bigBtn, ...S.bigBtnPay, marginTop: 6 }} onClick={saveForm}>
              {form.id ? "Save changes" : "Add shutter"}
            </button>
          </Sheet>
        )}
      </div>
    </div>
  );
}

function Field({ label, value, onChange, placeholder, flex }) {
  return (
    <label style={{ ...S.field, ...(flex ? { flex: 1 } : {}) }}>
      <span style={S.fieldLabel}>{label}</span>
      <input style={{ ...S.glass, ...S.input }} value={value} placeholder={placeholder}
        onChange={(e) => onChange(e.target.value)} />
    </label>
  );
}

function Sheet({ children, onClose }) {
  return (
    <div style={S.overlay} onClick={onClose}>
      <div style={S.sheet} className="sheet" onClick={(e) => e.stopPropagation()}>
        <div style={S.grabber} />
        {children}
      </div>
    </div>
  );
}

/* ── styles ── */
const CSS = `
@import url('https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,500;9..144,600&family=Hanken+Grotesk:wght@400;500;600;700&display=swap');
:root{ --muted:rgba(226,230,255,.82); }
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent;}
.row{transition:background .15s,transform .1s;}
.row:active{transform:scale(.985);background:rgba(255,255,255,.16)!important;}
.pill:active{transform:scale(.94);}
.fab:active{transform:scale(.9);}
.sheet{animation:slideUp .3s cubic-bezier(.2,.8,.2,1);}
@keyframes slideUp{from{transform:translateY(100%);}to{transform:translateY(0);}}
@keyframes drift{0%{transform:translate(0,0) scale(1);}50%{transform:translate(18px,-22px) scale(1.08);}100%{transform:translate(0,0) scale(1);}}
input{font-family:'Hanken Grotesk',sans-serif;}
input::placeholder{color:rgba(255,255,255,.4);}
::-webkit-scrollbar{display:none;}
`;

const glass = {
  background: "rgba(24,36,68,.55)",
  backdropFilter: "blur(20px) saturate(150%)",
  WebkitBackdropFilter: "blur(20px) saturate(150%)",
  border: "1px solid rgba(255,255,255,.16)",
  boxShadow: "0 8px 32px rgba(6,6,24,.4), inset 0 1px 0 rgba(255,255,255,.18)",
};

const S = {
  glass,
  root: { display: "flex", justifyContent: "center", padding: 16, background: "#0a0a14", minHeight: "100vh", fontFamily: "'Hanken Grotesk', sans-serif" },
  phone: { width: 390, height: 800, borderRadius: 34, position: "relative", overflow: "hidden", color: "#F5F6FF", boxShadow: "0 40px 90px rgba(0,0,0,.6)" },

  bg: { position: "absolute", inset: 0, background: "linear-gradient(160deg,#22365f 0%,#192a4f 45%,#0e1830 100%)", overflow: "hidden" },
  orb: { position: "absolute", borderRadius: "50%", filter: "blur(60px)", opacity: .5, animation: "drift 14s ease-in-out infinite" },
  orbA: { width: 260, height: 260, background: "#ff6600", top: -60, left: -50 },
  orbB: { width: 220, height: 220, background: "#2f5aa0", top: 120, right: -70, animationDelay: "-4s" },
  orbC: { width: 240, height: 240, background: "#ff8a3d", bottom: 80, left: -60, animationDelay: "-8s" },
  orbD: { width: 200, height: 200, background: "#274074", bottom: -50, right: -30, animationDelay: "-2s" },
  grain: { position: "absolute", inset: 0, opacity: .25, background: "radial-gradient(rgba(255,255,255,.1) 1px,transparent 1px)", backgroundSize: "3px 3px" },

  scroll: { position: "absolute", inset: 0, overflowY: "auto", padding: "0 0 0" },

  header: { padding: "22px 18px 8px", display: "flex", flexDirection: "column", gap: 14 },
  brandRow: { display: "flex", alignItems: "center", gap: 9 },
  brandMark: { width: 28, height: 28, borderRadius: 9, background: "rgba(255,255,255,.15)", border: "1px solid rgba(255,255,255,.25)", color: "#fff", display: "grid", placeItems: "center" },
  brand: { fontSize: 16, fontWeight: 700, letterSpacing: "-0.01em" },
  monthNav: { display: "flex", alignItems: "center", justifyContent: "space-between", borderRadius: 16, padding: 6 },
  navBtn: { width: 40, height: 36, border: "none", background: "transparent", color: "#fff", display: "grid", placeItems: "center", cursor: "pointer", borderRadius: 10 },
  monthLabel: { textAlign: "center", display: "flex", flexDirection: "column", lineHeight: 1.05 },
  monthName: { fontFamily: "'Fraunces', serif", fontSize: 19, fontWeight: 600 },
  monthYear: { fontSize: 11, color: "var(--muted)", fontWeight: 600, letterSpacing: ".06em" },

  summary: { position: "relative", margin: "8px 18px 4px", padding: "18px 20px 16px", borderRadius: 22, overflow: "hidden" },
  sheen: { position: "absolute", top: 0, left: 0, right: 0, height: "55%", background: "linear-gradient(180deg,rgba(255,255,255,.16),transparent)", pointerEvents: "none" },
  sumTop: { display: "flex", justifyContent: "space-between", alignItems: "center" },
  sumLabel: { fontSize: 12.5, color: "rgba(226,230,255,.82)", fontWeight: 500 },
  sumPct: { fontSize: 12.5, fontWeight: 700, color: "#ff8a3d" },
  bigNum: { fontFamily: "'Fraunces', serif", fontSize: 37, fontWeight: 600, letterSpacing: "-0.02em", marginTop: 6, textShadow: "0 2px 20px rgba(0,0,0,.25)" },
  ofExpected: { fontSize: 12.5, color: "rgba(226,230,255,.7)", marginTop: 1 },
  bar: { height: 7, background: "rgba(255,255,255,.14)", borderRadius: 99, marginTop: 14, overflow: "hidden" },
  barFill: { height: "100%", background: "linear-gradient(90deg,#ff6600,#ff9a4d)", borderRadius: 99, transition: "width .4s ease", boxShadow: "0 0 14px rgba(255,102,0,.55)" },
  sumStats: { display: "flex", gap: 10, marginTop: 14 },
  statChip: { flex: 1, display: "flex", alignItems: "center", gap: 6, background: "rgba(255,255,255,.08)", border: "1px solid rgba(255,255,255,.12)", borderRadius: 12, padding: "9px 11px", fontSize: 12.5 },

  controls: { padding: "14px 18px 8px", display: "flex", flexDirection: "column", gap: 11 },
  searchWrap: { display: "flex", alignItems: "center", gap: 9, borderRadius: 14, padding: "11px 13px" },
  search: { flex: 1, border: "none", background: "transparent", outline: "none", fontSize: 14.5, color: "#fff" },
  chips: { display: "flex", gap: 8 },
  chip: { color: "rgba(255,255,255,.7)", padding: "8px 16px", borderRadius: 99, fontSize: 13, fontWeight: 600, cursor: "pointer", fontFamily: "inherit" },
  chipOn: { background: "#ff6600", color: "#fff", border: "1px solid rgba(255,154,77,.7)" },

  list: { padding: "6px 14px 0" },
  empty: { textAlign: "center", color: "var(--muted)", padding: 40, fontSize: 14 },
  row: { display: "flex", alignItems: "center", gap: 12, padding: "11px 12px", borderRadius: 18, cursor: "pointer", marginBottom: 9 },
  avatar: { width: 44, height: 44, borderRadius: 13, display: "grid", placeItems: "center", flexShrink: 0, border: "1px solid rgba(255,255,255,.16)" },
  avatarTxt: { fontFamily: "'Fraunces', serif", fontWeight: 600, fontSize: 13 },
  rowMid: { flex: 1, minWidth: 0 },
  tenant: { fontSize: 15, fontWeight: 600, letterSpacing: "-0.01em" },
  biz: { fontSize: 12.5, color: "var(--muted)", marginTop: 1 },
  rowRight: { display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 6 },
  rent: { fontSize: 14, fontWeight: 700, fontVariantNumeric: "tabular-nums" },
  pill: { display: "flex", alignItems: "center", gap: 4, borderRadius: 99, padding: "5px 11px", fontSize: 11.5, fontWeight: 700, cursor: "pointer", fontFamily: "inherit", transition: "transform .1s" },
  pillPaid: { background: "rgba(52,211,153,.18)", color: "#4ee0a8", border: "1px solid rgba(52,211,153,.45)" },
  pillDue: { background: "rgba(255,102,0,.2)", color: "#ff9a52", border: "1px solid rgba(255,102,0,.38)" },

  fab: { position: "absolute", right: 18, bottom: 22, width: 58, height: 58, borderRadius: 19, border: "1px solid rgba(255,255,255,.35)", background: "linear-gradient(135deg,#ff6600,#ff9a4d)", color: "#fff", display: "grid", placeItems: "center", cursor: "pointer", boxShadow: "0 12px 32px rgba(255,102,0,.5), inset 0 1px 0 rgba(255,255,255,.5)", transition: "transform .12s" },

  overlay: { position: "absolute", inset: 0, background: "rgba(10,8,25,.5)", backdropFilter: "blur(3px)", WebkitBackdropFilter: "blur(3px)", display: "flex", alignItems: "flex-end", zIndex: 20 },
  sheet: { width: "100%", background: "rgba(20,30,58,.78)", backdropFilter: "blur(30px) saturate(160%)", WebkitBackdropFilter: "blur(30px) saturate(160%)", borderTop: "1px solid rgba(255,255,255,.22)", borderRadius: "28px 28px 34px 34px", padding: "10px 22px 26px", maxHeight: "85%", overflowY: "auto", boxShadow: "0 -20px 60px rgba(0,0,0,.5)" },
  grabber: { width: 38, height: 4, borderRadius: 99, background: "rgba(255,255,255,.3)", margin: "4px auto 16px" },

  sheetHead: { display: "flex", alignItems: "center", gap: 11, marginBottom: 18 },
  iconBtn: { width: 38, height: 38, borderRadius: 12, color: "#fff", display: "grid", placeItems: "center", cursor: "pointer" },
  detailGrid: { display: "flex", gap: 11, marginBottom: 16 },
  detailCell: { flex: 1, borderRadius: 14, padding: "12px 14px", display: "flex", flexDirection: "column", gap: 3 },
  detailLabel: { fontSize: 11.5, color: "var(--muted)", fontWeight: 600 },
  detailVal: { fontFamily: "'Fraunces', serif", fontSize: 18, fontWeight: 600 },

  bigBtn: { width: "100%", borderRadius: 15, padding: "15px", fontSize: 14.5, fontWeight: 700, cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center", gap: 7, fontFamily: "inherit", border: "1px solid rgba(255,255,255,.3)" },
  bigBtnPay: { background: "linear-gradient(135deg,#ff6600,#ff9a4d)", color: "#fff", boxShadow: "0 8px 26px rgba(255,102,0,.45)" },
  bigBtnUndo: { background: "rgba(52,211,153,.12)", color: "#4ee0a8", border: "1px solid rgba(52,211,153,.45)" },

  histLabel: { fontSize: 12.5, fontWeight: 700, color: "var(--muted)", margin: "20px 0 10px", letterSpacing: ".02em" },
  histStrip: { display: "flex", justifyContent: "space-between", gap: 6 },
  histCell: { display: "flex", flexDirection: "column", alignItems: "center", gap: 6, flex: 1 },
  histDot: { width: 36, height: 36, borderRadius: 11, display: "grid", placeItems: "center", fontWeight: 700, fontSize: 13, border: "1px solid transparent" },
  histM: { fontSize: 11, color: "var(--muted)", fontWeight: 600 },

  formTitle: { fontFamily: "'Fraunces', serif", fontSize: 22, fontWeight: 600, marginBottom: 18 },
  field: { display: "flex", flexDirection: "column", gap: 6, marginBottom: 13 },
  fieldLabel: { fontSize: 12.5, fontWeight: 600, color: "var(--muted)" },
  input: { borderRadius: 12, padding: "12px 14px", fontSize: 15, color: "#fff", outline: "none" },
};
