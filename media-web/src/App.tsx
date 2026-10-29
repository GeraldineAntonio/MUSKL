import { useEffect, useRef, useState, type FormEvent } from 'react';
import { Camera, Check, ChevronDown, CircleStop, Dumbbell, LogOut, Plus, RefreshCw, Search, ShieldCheck, Upload, Video } from 'lucide-react';

type User = { role: string; status: string; first_name?: string; last_name?: string };
type Exercise = { id: string; name: string; muscle_group: string; equipment: string; instructions?: string | null; media_url?: string | null; media_mime?: string | null };
type Session = { token: string; user: User };
const API = (import.meta.env.VITE_MUSKL_API_URL || 'https://muskl-api.onrender.com').replace(/\/$/, '');
const SESSION_KEY = 'muskl-media-session';

function savedSession(): Session | null {
  try { return JSON.parse(sessionStorage.getItem(SESSION_KEY) || 'null') as Session | null; }
  catch { return null; }
}

async function api<T>(path: string, token: string, options: RequestInit = {}): Promise<T> {
  const headers = new Headers(options.headers);
  headers.set('Authorization', `Bearer ${token}`);
  if (options.body && !(options.body instanceof FormData)) headers.set('Content-Type', 'application/json');
  const response = await fetch(`${API}${path}`, { ...options, headers });
  if (!response.ok) {
    let message = `Error ${response.status}`;
    try {
      const body = await response.json();
      message = body.detail?.message || body.detail || body.message || message;
      if (typeof message !== 'string') message = JSON.stringify(message);
    } catch { /* The API may return an empty response. */ }
    throw new Error(message);
  }
  return response.status === 204 ? undefined as T : response.json() as Promise<T>;
}

function Login({ onLogin }: { onLogin: (session: Session) => void }) {
  const [identifier, setIdentifier] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  async function submit(event: FormEvent) {
    event.preventDefault(); setError(''); setBusy(true);
    try {
      const result = await fetch(`${API}/api/v1/auth/login`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ identifier, password }),
      });
      const body = await result.json();
      if (!result.ok) throw new Error(body.detail?.message || body.detail || 'No se pudo iniciar sesión.');
      const session: Session = { token: body.access_token, user: body.user };
      if (!session.token || !['trainer', 'admin'].includes(session.user.role) || session.user.status !== 'active') {
        throw new Error('Ingresa con una cuenta activa de entrenador o administrador.');
      }
      sessionStorage.setItem(SESSION_KEY, JSON.stringify(session)); onLogin(session);
    } catch (e) { setError(e instanceof Error ? e.message : 'Error de conexión con MUSKL.'); }
    finally { setBusy(false); }
  }
  return <main className="login-layout">
    <div className="brand-mark"><Dumbbell size={25} /></div>
    <p className="eyebrow">HERRAMIENTA MUSKL · ENTRENADOR Y ADMINISTRADOR</p>
    <h1>Videos para<br /><span>cada ejercicio.</span></h1>
    <p className="lead">Graba una demostración con tu cámara y quedará vinculada al catálogo de ejercicios de MUSKL.</p>
    <form className="login-card" onSubmit={submit}>
      <label>Correo o número de socio<input autoComplete="username" value={identifier} onChange={e => setIdentifier(e.target.value)} required /></label>
      <label>Contraseña<input type="password" autoComplete="current-password" value={password} onChange={e => setPassword(e.target.value)} required /></label>
      {error && <p className="error">{error}</p>}
      <button className="primary wide" disabled={busy}>{busy ? 'Conectando…' : 'Iniciar sesión'}</button>
      <p className="secure-note"><ShieldCheck size={15} /> Acceso protegido por tu cuenta MUSKL</p>
    </form>
  </main>;
}

function Recorder({ exercise, token, onUploaded }: { exercise: Exercise; token: string; onUploaded: (value: Exercise) => void }) {
  const liveRef = useRef<HTMLVideoElement>(null);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const [preview, setPreview] = useState('');
  const [recording, setRecording] = useState(false);
  const [cameraReady, setCameraReady] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  useEffect(() => () => {
    recorderRef.current?.state === 'recording' && recorderRef.current.stop();
    streamRef.current?.getTracks().forEach(track => track.stop());
    if (preview) URL.revokeObjectURL(preview);
  }, [preview]);

  async function openCamera() {
    setError(''); setSuccess('');
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment', width: { ideal: 1280 }, height: { ideal: 720 } }, audio: false });
      streamRef.current = stream;
      if (liveRef.current) liveRef.current.srcObject = stream;
      setCameraReady(true);
    } catch { setError('No pudimos abrir la cámara. Revisa el permiso del navegador y usa una conexión HTTPS.'); }
  }

  function startRecording() {
    const stream = streamRef.current;
    if (!stream) return;
    const mime = ['video/mp4;codecs=avc1.42E01E', 'video/mp4', 'video/webm;codecs=vp9', 'video/webm']
      .find(value => MediaRecorder.isTypeSupported(value));
    if (!mime) { setError('Este navegador no ofrece un formato de video compatible.'); return; }
    chunksRef.current = [];
    const recorder = new MediaRecorder(stream, { mimeType: mime, videoBitsPerSecond: 1800000 });
    recorderRef.current = recorder;
    recorder.ondataavailable = event => { if (event.data.size) chunksRef.current.push(event.data); };
    recorder.onstop = () => {
      const blob = new Blob(chunksRef.current, { type: mime.split(';')[0] });
      if (preview) URL.revokeObjectURL(preview);
      setPreview(URL.createObjectURL(blob)); setRecording(false);
      stream.getTracks().forEach(track => track.stop()); streamRef.current = null;
      setCameraReady(false);
    };
    recorder.start(); setRecording(true); setError(''); setSuccess('');
  }

  function stopRecording() { recorderRef.current?.stop(); }
  function retake() { if (preview) URL.revokeObjectURL(preview); setPreview(''); setSuccess(''); void openCamera(); }

  async function upload() {
    if (!preview) return;
    const response = await fetch(preview);
    const blob = await response.blob();
    if (blob.size > 50 * 1024 * 1024) { setError('El video supera el límite de 50 MB. Graba una toma más corta.'); return; }
    const extension = blob.type.includes('mp4') ? 'mp4' : blob.type.includes('quicktime') ? 'mov' : 'webm';
    const data = new FormData(); data.append('video', blob, `${exercise.name.toLowerCase().replace(/[^a-z0-9]+/g, '-')}.${extension}`);
    setBusy(true); setError(''); setSuccess('');
    try {
      const saved = await api<{ media_url: string; media_mime: string }>(`/api/v1/trainer/exercises/${exercise.id}/media`, token, { method: 'POST', body: data });
      onUploaded({ ...exercise, ...saved }); setSuccess('Video guardado y disponible en la rutina del socio.');
      setPreview('');
    } catch (e) { setError(e instanceof Error ? e.message : 'No se pudo subir el video.'); }
    finally { setBusy(false); }
  }

  return <section className="recorder-card">
    <div className="recorder-title"><div><p className="eyebrow">EJERCICIO SELECCIONADO</p><h2>{exercise.name}</h2><p className="muted">{exercise.muscle_group} · {exercise.equipment}</p></div><span className="tag">{exercise.media_url ? 'Tiene video' : 'Sin video'}</span></div>
    {exercise.media_url && <div className="existing-media">{exercise.media_mime?.startsWith('video/') ? <video controls playsInline src={exercise.media_url} /> : <img src={exercise.media_url} alt={`Demostración de ${exercise.name}`} />}</div>}
    <div className="camera-stage">
      {preview ? <video className="camera-video" src={preview} controls playsInline /> : <video ref={liveRef} className={`camera-video ${cameraReady ? '' : 'hidden'}`} autoPlay muted playsInline />}
      {!cameraReady && !preview && <div className="camera-placeholder"><Camera size={34} /><span>Tu vista previa aparecerá aquí</span></div>}
      {recording && <div className="recording-indicator"><i /> Grabando</div>}
    </div>
    <div className="recorder-actions">
      {!cameraReady && !preview && <button className="primary" onClick={openCamera}><Camera size={17} /> Activar cámara</button>}
      {cameraReady && !recording && <button className="primary" onClick={startRecording}><Video size={17} /> Grabar video</button>}
      {recording && <button className="danger" onClick={stopRecording}><CircleStop size={17} /> Detener grabación</button>}
      {preview && <><button className="secondary" onClick={retake}><RefreshCw size={16} /> Repetir</button><button className="primary" disabled={busy} onClick={upload}><Upload size={16} /> {busy ? 'Subiendo…' : 'Guardar video'}</button></>}
    </div>
    <p className="hint">MP4, MOV o WebM · máximo 50 MB · se guarda en el almacenamiento privado de MUSKL.</p>
    {error && <p className="error">{error}</p>}{success && <p className="success"><Check size={16} />{success}</p>}
  </section>;
}

function Workspace({ session, onLogout }: { session: Session; onLogout: () => void }) {
  const [exercises, setExercises] = useState<Exercise[]>([]);
  const [selected, setSelected] = useState<Exercise | null>(null);
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [showCreate, setShowCreate] = useState(false);
  const [createdMessage, setCreatedMessage] = useState('');
  useEffect(() => {
    let alive = true;
    setLoading(true); setError('');
    const query = search.trim() ? `?search=${encodeURIComponent(search.trim())}` : '';
    api<Exercise[]>(`/api/v1/trainer/exercises${query}`, session.token)
      .then(rows => { if (alive) { setExercises(rows); if (selected) setSelected(rows.find(item => item.id === selected.id) || null); } })
      .catch(e => { if (alive) setError(e instanceof Error ? e.message : 'No se pudo cargar el catálogo.'); })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, [search, session.token]);
  return <div className="app-shell">
    <header className="topbar"><a className="wordmark" href="#"><span className="brand-mark small"><Dumbbell size={19} /></span><b>MUSKL</b><span className="divider" />Videos de ejercicios</a><div className="user-area"><span>{session.user.first_name || 'Entrenador'} {session.user.last_name || ''}</span><button className="icon-button" title="Cerrar sesión" onClick={onLogout}><LogOut size={18} /></button></div></header>
    <main className="workspace"><div className="intro"><p className="eyebrow">CATÁLOGO MUSKL</p><h1>Graba una demostración.</h1><p>El video se asociará al ejercicio y se mostrará en la rutina del socio.</p></div>
      <div className="content-grid"><aside className={"exercise-panel " + (showCreate ? "creating" : "")}><div className="searchbox"><Search size={17} /><input value={search} onChange={e => setSearch(e.target.value)} placeholder="Buscar ejercicio" /></div>
        <button className="primary create-exercise-button" onClick={() => { setShowCreate(value => !value); setCreatedMessage(''); }}><Plus size={16} />{showCreate ? 'Cerrar formulario' : 'Agregar ejercicio'}</button>
        {showCreate && <CreateExercise token={session.token} onCreated={exercise => { setExercises(current => [exercise, ...current.filter(item => item.id !== exercise.id)]); setSelected(exercise); setSearch(exercise.name); setShowCreate(false); setCreatedMessage(`“${exercise.name}” se agregó al catálogo.`); }} />}
        {createdMessage && <p className="success state"><Check size={15} />{createdMessage}</p>}
        {loading && <p className="muted state">Cargando ejercicios…</p>}{error && <p className="error state">{error}</p>}
        {!loading && !error && exercises.length === 0 && <p className="muted state">No hay ejercicios con esa búsqueda.</p>}
        <div className="exercise-list">{exercises.map(item => <button key={item.id} className={`exercise-row ${selected?.id === item.id ? 'active' : ''}`} onClick={() => setSelected(item)}><span className="exercise-icon"><Dumbbell size={18} /></span><span className="exercise-copy"><b>{item.name}</b><small>{item.muscle_group} · {item.equipment}</small></span>{item.media_url && <span className="dot" title="Tiene multimedia" />}<ChevronDown className="row-arrow" size={15} /></button>)}</div>
      </aside>
      <div className="detail-panel">{selected ? <Recorder key={selected.id} exercise={selected} token={session.token} onUploaded={saved => { setSelected(saved); setExercises(current => current.map(item => item.id === saved.id ? saved : item)); }} /> : <div className="empty-state"><div className="empty-icon"><Camera size={28} /></div><h2>Elige un ejercicio</h2><p>Selecciona uno del catálogo para abrir la cámara y grabar su demostración.</p></div>}</div></div>
      <footer><ShieldCheck size={15} /> Solo tu cuenta activa de entrenador puede modificar el catálogo.</footer>
    </main>
  </div>;
}

const MUSCLE_GROUPS = ['Pecho', 'Espalda', 'Hombros', 'Bíceps', 'Tríceps', 'Piernas', 'Piernas y glúteos', 'Glúteos', 'Pantorrillas', 'Abdomen', 'Cardio', 'Cuerpo completo'];
const EQUIPMENT = ['Peso corporal', 'Mancuernas', 'Barra', 'Barra y discos', 'Discos', 'Poleas', 'Máquina', 'Bandas elásticas', 'Kettlebell', 'Otro'];

function CreateExercise({ token, onCreated }: { token: string; onCreated: (exercise: Exercise) => void }) {
  const [name, setName] = useState('');
  const [muscle, setMuscle] = useState(MUSCLE_GROUPS[0]);
  const [equipment, setEquipment] = useState(EQUIPMENT[0]);
  const [instructions, setInstructions] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  async function submit(event: FormEvent) {
    event.preventDefault(); setError(''); setBusy(true);
    try {
      const exercise = await api<Exercise>('/api/v1/trainer/exercises', token, {
        method: 'POST', body: JSON.stringify({ name, muscle_group: muscle, equipment, instructions: instructions.trim() || null }),
      });
      onCreated(exercise);
    } catch (e) { setError(e instanceof Error ? e.message : 'No se pudo guardar el ejercicio.'); }
    finally { setBusy(false); }
  }
  return <form className="create-exercise-form" onSubmit={submit}>
    <p className="eyebrow">NUEVO EJERCICIO</p>
    <label>Nombre<input value={name} onChange={e => setName(e.target.value)} maxLength={120} placeholder="Ej. Remo unilateral en polea" required /></label>
    <label>Grupo muscular<select value={muscle} onChange={e => setMuscle(e.target.value)}>{MUSCLE_GROUPS.map(value => <option key={value}>{value}</option>)}</select></label>
    <label>Equipo<select value={equipment} onChange={e => setEquipment(e.target.value)}>{EQUIPMENT.map(value => <option key={value}>{value}</option>)}</select></label>
    <label>Cómo se hace <span className="optional">(opcional, editable)</span><textarea value={instructions} onChange={e => setInstructions(e.target.value)} maxLength={2000} rows={3} placeholder="Escribe los pasos y recomendaciones del ejercicio." /></label>
    <p className="form-note">Después de guardarlo podrás grabar o subir su video. Las series, repeticiones y descanso se configuran al crear la rutina.</p>
    {error && <p className="error">{error}</p>}
    <button className="primary wide" disabled={busy || name.trim().length < 2}>{busy ? 'Guardando…' : 'Guardar y grabar video'}</button>
  </form>;
}


function AdminWorkspace({ session, onLogout }: { session: Session; onLogout: () => void }) {
  const [exercises, setExercises] = useState<Exercise[]>([]);
  const [selected, setSelected] = useState<Exercise | null>(null);
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  useEffect(() => {
    let alive = true;
    setLoading(true); setError('');
    const query = search.trim() ? `?search=${encodeURIComponent(search.trim())}` : '';
    api<Exercise[]>(`/api/v1/admin/exercises${query}`, session.token)
      .then(rows => { if (alive) { setExercises(rows); setSelected(current => current ? rows.find(item => item.id === current.id) || null : null); } })
      .catch(e => { if (alive) setError(e instanceof Error ? e.message : 'No se pudo cargar el catálogo.'); })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, [search, session.token]);
  function updateExercise(saved: Exercise) {
    setExercises(current => current.map(item => item.id === saved.id ? saved : item));
    setSelected(saved);
  }
  return <div className="app-shell">
    <header className="topbar"><a className="wordmark" href="#"><span className="brand-mark small"><Dumbbell size={19} /></span><b>MUSKL</b><span className="divider" />Administración de ejercicios</a><div className="user-area"><span>{session.user.first_name || 'Administrador'} {session.user.last_name || ''}</span><button className="icon-button" title="Cerrar sesión" onClick={onLogout}><LogOut size={18} /></button></div></header>
    <main className="workspace"><div className="intro"><p className="eyebrow">PANEL DE ADMINISTRACIÓN</p><h1>Catálogo y videos.</h1><p>Consulta las demostraciones y actualiza los datos de cada ejercicio.</p></div>
      <div className="content-grid"><aside className="exercise-panel"><div className="searchbox"><Search size={17} /><input value={search} onChange={e => setSearch(e.target.value)} placeholder="Buscar por nombre, músculo o equipo" /></div>
        {loading && <p className="muted state">Cargando ejercicios…</p>}{error && <p className="error state">{error}</p>}
        {!loading && !error && exercises.length === 0 && <p className="muted state">No hay ejercicios con esa búsqueda.</p>}
        <div className="exercise-list">{exercises.map(item => <button key={item.id} className={`exercise-row ${selected?.id === item.id ? 'active' : ''}`} onClick={() => setSelected(item)}><span className="exercise-icon"><Dumbbell size={18} /></span><span className="exercise-copy"><b>{item.name}</b><small>{item.muscle_group} · {item.equipment}</small></span>{item.media_url && <span className="dot" title="Tiene video" />}<ChevronDown className="row-arrow" size={15} /></button>)}</div>
      </aside><div className="detail-panel">{selected ? <AdminExerciseEditor key={selected.id} exercise={selected} token={session.token} onSaved={updateExercise} /> : <div className="empty-state"><div className="empty-icon"><Video size={28} /></div><h2>Elige un ejercicio</h2><p>Podrás ver el video guardado y editar nombre, grupo muscular, equipo e instrucciones.</p></div>}</div></div>
      <footer><ShieldCheck size={15} /> Acceso exclusivo para cuentas activas de administrador.</footer>
    </main>
  </div>;
}

function AdminExerciseEditor({ exercise, token, onSaved }: { exercise: Exercise; token: string; onSaved: (value: Exercise) => void }) {
  const [name, setName] = useState(exercise.name);
  const [muscle, setMuscle] = useState(exercise.muscle_group);
  const [equipment, setEquipment] = useState(exercise.equipment);
  const [instructions, setInstructions] = useState(exercise.instructions || '');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  async function save(event: FormEvent) {
    event.preventDefault(); setBusy(true); setError(''); setMessage('');
    try {
      const saved = await api<Exercise>(`/api/v1/admin/exercises/${exercise.id}`, token, { method: 'PUT', body: JSON.stringify({ name, muscle_group: muscle, equipment, instructions: instructions.trim() || null }) });
      onSaved(saved); setMessage('Datos del ejercicio actualizados.');
    } catch (e) { setError(e instanceof Error ? e.message : 'No se pudieron guardar los cambios.'); }
    finally { setBusy(false); }
  }
  async function replaceVideo(file?: File) {
    if (!file) return;
    if (!file.type.startsWith('video/')) { setError('Selecciona un archivo de video.'); return; }
    if (file.size > 50 * 1024 * 1024) { setError('El video debe pesar máximo 50 MB.'); return; }
    setBusy(true); setError(''); setMessage('');
    const data = new FormData(); data.append('video', file, file.name);
    try {
      const saved = await api<Partial<Exercise>>(`/api/v1/admin/exercises/${exercise.id}/media`, token, { method: 'POST', body: data });
      onSaved({ ...exercise, ...saved }); setMessage('Video actualizado.');
    } catch (e) { setError(e instanceof Error ? e.message : 'No se pudo actualizar el video.'); }
    finally { setBusy(false); }
  }
  return <section className="recorder-card admin-editor"><div className="recorder-title"><div><p className="eyebrow">EDITAR EJERCICIO</p><h2>{exercise.name}</h2><p className="muted">{exercise.muscle_group} · {exercise.equipment}</p></div><span className="tag">{exercise.media_url ? 'Video guardado' : 'Sin video'}</span></div>
    <div className="existing-media admin-video">{exercise.media_url ? exercise.media_mime?.startsWith('video/') ? <video controls playsInline src={exercise.media_url} /> : <img src={exercise.media_url} alt={`Demostración de ${exercise.name}`} /> : <div className="empty-video"><Video size={24} />Este ejercicio todavía no tiene video.</div>}</div>
    <label className="upload-replacement">{busy ? 'Guardando…' : 'Grabar desde la herramienta de entrenador o elegir video para reemplazar'}<input type="file" accept="video/mp4,video/webm,video/quicktime" disabled={busy} onChange={e => { void replaceVideo(e.target.files?.[0]); e.currentTarget.value = ''; }} /></label>
    <form className="create-exercise-form admin-form" onSubmit={save}>
      <label>Nombre<input value={name} onChange={e => setName(e.target.value)} maxLength={120} required /></label>
      <label>Grupo muscular<select value={muscle} onChange={e => setMuscle(e.target.value)}>{MUSCLE_GROUPS.map(value => <option key={value}>{value}</option>)}</select></label>
      <label>Equipo<select value={equipment} onChange={e => setEquipment(e.target.value)}>{EQUIPMENT.map(value => <option key={value}>{value}</option>)}</select></label>
      <label>Instrucciones<textarea value={instructions} onChange={e => setInstructions(e.target.value)} maxLength={2000} rows={4} placeholder="Indicaciones para realizar el ejercicio." /></label>
      {error && <p className="error">{error}</p>}{message && <p className="success"><Check size={16} />{message}</p>}
      <button className="primary" disabled={busy || name.trim().length < 2}>{busy ? 'Guardando…' : 'Guardar cambios'}</button>
    </form>
  </section>;
}

export default function App() {
  const [session, setSession] = useState<Session | null>(() => savedSession());
  function logout() { sessionStorage.removeItem(SESSION_KEY); setSession(null); }
  return session ? session.user.role === 'admin' ? <AdminWorkspace session={session} onLogout={logout} /> : <Workspace session={session} onLogout={logout} /> : <Login onLogin={setSession} />;
}
