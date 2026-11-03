# Ionian Harness

Build. The agentic engineering setup I use to build with agents: one coordinator thread, context-isolated workers, gates enforced by hooks rather than by instruction.

Status: milestone 1, read gate and reader agent. Not ready for use.

Harness borrows from the best work I found: the zero-context review from Google's EGM, the TDD discipline from superpowers, the read gate from Spotify's shunt, the document shapes from spec-kit. I read them, learned, and built my own version. Where I kept their words, they are marked.

## Try the read gate

    cd <path-to-harness> && git init -q
    claude --plugin-dir .

Then: `What does line 200 of dev/big.txt say?` (denied once, reader dispatched, targeted read passes) and `Read dev/big.txt lines 10 to 12.` (passes directly).

License: MIT.
