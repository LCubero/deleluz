// Web Bluetooth link to the LEDDMX controller (GATT FFE0/FFE1, write without response).
// Wire format: docs/PROTOCOL.md. Simulation logs frames instead of writing them.
const SERVICE = 0xffe0;
const WRITE = 0xffe1;

export function createLink({ onChange, simulate = false }) {
  const supported = typeof navigator !== 'undefined' && !!navigator.bluetooth;
  const state = {
    status: simulate || !supported ? 'simulated' : 'idle', // idle | connecting | connected | lost | simulated
    name: simulate || !supported ? 'Simulated strip' : null,
    lostAt: null,
    error: null,
    supported,
  };
  let device;
  let writer;

  const set = patch => { Object.assign(state, patch); onChange?.({ ...state }); };

  function lost() {
    writer = undefined;
    set({ status: 'lost', lostAt: Date.now() });
  }

  async function open() {
    // Lab runs 5-5b: about half of fresh connects fail at once with "Connection attempt failed";
    // an immediate retry usually works.
    let server;
    for (let attempt = 1; ; attempt++) {
      try { server = await device.gatt.connect(); break; }
      catch (error) {
        if (attempt >= 4 || !/attempt failed/i.test(error.message)) throw error;
        await new Promise(resolve => setTimeout(resolve, 300));
      }
    }
    const service = await server.getPrimaryService(SERVICE);
    const characteristic = await service.getCharacteristic(WRITE);
    if (!characteristic.properties.writeWithoutResponse) throw new Error('This controller does not accept commands (FFE1).');
    writer = characteristic;
  }

  async function connect({ choose }) {
    if (state.status === 'simulated') return;
    set({ status: 'connecting', error: null });
    try {
      if (choose || !device) {
        const chosen = await navigator.bluetooth.requestDevice({ filters: [{ namePrefix: 'LEDDMX' }], optionalServices: [SERVICE] });
        device?.removeEventListener('gattserverdisconnected', lost);
        device = chosen;
        device.addEventListener('gattserverdisconnected', lost);
      }
      await open();
      set({ status: 'connected', name: device.name ?? 'LEDDMX', lostAt: null });
    } catch (error) {
      if (device?.gatt.connected) device.gatt.disconnect();
      writer = undefined;
      const canceled = error.name === 'NotFoundError';
      set({ status: state.lostAt ? 'lost' : 'idle', error: canceled ? null : error.message });
      if (!canceled) throw error;
    }
  }

  return {
    state,
    connect: () => connect({ choose: true }),
    reconnect: () => connect({ choose: false }),
    get ready() { return state.status === 'connected' || state.status === 'simulated'; },
    async write(bytes) {
      if (state.status === 'simulated') {
        console.debug('SIM', Array.from(bytes, b => b.toString(16).padStart(2, '0')).join(' '));
        return;
      }
      if (!writer) throw new Error('Not connected');
      await writer.writeValueWithoutResponse(bytes);
    },
  };
}
