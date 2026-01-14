local Signal = require(script.Parent.Replica.ReplicaShared.Signal)

export type ValueChangedSignal = Signal.Signal<any, any>
export type ValueInsertedSignal = Signal.Signal<any, number?>
export type ValueRemovedSignal = Signal.Signal<any, number>

export type ValueChangedSignals = { [string]: ValueChangedSignal } | { [string | number]: ValueChangedSignals }
export type ValueInsertedSignals = { [string]: ValueInsertedSignal } | { [string | number]: ValueInsertedSignals }
export type ValueRemovedSignals = { [string]: ValueRemovedSignal } | { [string | number]: ValueRemovedSignals }

return {}