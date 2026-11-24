export const SCENES_KEY = 'deleluz.webapp.scenes';

export function loadScenes(storage) {
  try {
    const scenes = JSON.parse(storage.getItem(SCENES_KEY));
    return Array.isArray(scenes) ? scenes.filter(scene => typeof scene?.name === 'string') : [];
  } catch { return []; }
}

export function saveScene(storage, name, mode) {
  const trimmed = name.trim();
  if ([...trimmed].length < 1 || [...trimmed].length > 30) throw new Error('Enter a name with 1–30 characters.');
  const scenes = loadScenes(storage);
  if (scenes.some(scene => scene.name.toLowerCase() === trimmed.toLowerCase())) throw new Error('A scene with that name already exists.');
  const scene = { ...mode, name: trimmed };
  storage.setItem(SCENES_KEY, JSON.stringify([...scenes, scene]));
  return scene;
}

export function deleteScene(storage, name) {
  storage.setItem(SCENES_KEY, JSON.stringify(loadScenes(storage).filter(scene => scene.name !== name)));
}
