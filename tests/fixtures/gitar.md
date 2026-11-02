<details>
<summary><b>Code Review</b> <kbd>✅ Approved</kbd> <kbd>4 closed / 4 findings</kbd></summary>

<kbd>🟡 Medium risk</kbd> · The new FIL resolver derives CAN IDs and payload bytes from named scenarios; mapping errors could invalidate or weaken vehicle-test results.

Adds FIL stimuli generation from named CAN scenarios in `tests/fil/scenarios/*.json`, wiring `generate_stimuli` into the Canpiler pipeline and writing outputs to the gitignored `tests/fil/stimuli/`. Both resolved findings were addressed: scaling now matches the firmware's float32 PACK behavior, and out-of-range physical values are rejected with `FilScenarioError` instead of being silently masked. The FIL generator unit tests were removed and the README no longer mentions the stimuli prerequisite for `run_tests`, so payload packing is currently untested. No open findings remain, so the change is approved.

<details>
<summary><kbd>✅ 4 closed</kbd></summary>

<details>
<summary>✅ <b>Bug:</b> Scaling uses double division, not the firmware's float32 PACK_COEFF multiply</summary>

> <kbd>📄 generators/canpiler/fil/generator.py:155-169</kbd> <kbd>📄 tests/fil/README.md:35-37</kbd>
> `_pack_signal` computes `int((value - offset) / scale)` in double precision. The generated firmware does something different: it multiplies by `static constexpr float PACK_COEFF_* = 1/scale` and casts, e.g. `(int16_t)(x * PACK_COEFF_...)` (see `node_header.h.jinja:43` and `firmware/source/a_box/main.c:213`). For many ordinary physical values the two truncate differently. With scale 0.1, `0.7/0.1` is 6.9999999999999991, so Python gives 6. Firmware computes `0.7f * 10.0f`, which rounds to exactly 7.0f, so it gives 7. The same happens for 2.3 (22 vs 23), 4.35, 0.3, 1.9 and others. The current scenario only works because 214 and -50 happen to divide exactly. Any future expectation such as `AMK_PositiveTorqueLimit: 21.3` would produce a payload the firmware never sends, and the FIL test would fail even though the firmware behaves correctly. That contradicts the README's claim of matching "the same scale/offset ... rules as the generated firmware macros". To mirror firmware, do the math in float32 and multiply by the float32 reciprocal, as in the suggested fix.

</details>

<details>
<summary>✅ <b>Edge Case:</b> Out-of-range physical values are silently masked into wrong payloads</summary>

> <kbd>📄 generators/canpiler/fil/generator.py:162-169</kbd>
> `_pack_signal` applies `raw &= signal.mask` without checking that the scaled value fits the signal's width and signedness. If a scenario uses a value beyond the signal's range (e.g. `AMK_PositiveTorqueLimit: 4000` → 40000, past int16; or a negative value on an unsigned signal), it silently wraps into a different bit pattern. The generator then emits a stimulus or expectation that doesn't match what the author wrote, with no error. Every other bad input (unknown bus, message, signal, or choice, and raw bytes out of range) raises `FilScenarioError`, so this case should raise too. Check the raw value against the signal's min/max for its length and signedness before masking, and raise `FilScenarioError` if it is out of range.

</details>

<details>
<summary>Closed: <b>Quality:</b> FIL generator unit tests deleted, leaving payload packing untested</summary>

> <kbd>📄 generators/canpiler/fil/generator.py:160-174</kbd>
> This change deletes `generators/canpiler/fil/tests/test_generator.py` (77 lines) and its `__init__.py`. Nothing replaces them, and no other test in the repo imports `canpiler.fil`. That leaves no test for `_pack_signal`, `_encode_scaled`, `_check_range`, `_choice_value`, or the big-endian byte swap in `generators/canpiler/fil/generator.py`. These are the functions that must match the firmware PACK macros bit for bit, and they are where both earlier findings were fixed: double vs. float32 scaling, and silent masking of out-of-range values. The CI `fil_tests` job only runs the end-to-end `ready_to_drive` scenario. So a regression in signedness, scale/offset, float, or byte-order handling would only show up as a wrong stimulus payload, and only for signals that scenario happens to use. Fix: restore the tests, or move them to wherever the generator Python tests now live. Add regression cases for the 0.7 @ scale 0.1 → 7 float32 case, rejection of out-of-range and negative-unsigned values, enum choice lookup, and big-endian 16/32-bit packing.

</details>

<details>
<summary>Closed: <b>Quality:</b> README no longer says generated stimuli must exist before run_tests</summary>

> <kbd>📄 tests/fil/README.md:32-39</kbd>
> This cleanup cut the note that `ready_to_drive.json` points to the generated `stimuli/ready_to_drive_stimuli.json`, and that the generator has to run once on a fresh checkout before `run_tests.py`. That file is gitignored (`.gitignore:36`). The firmware CMake files never invoke canpiler, so someone who follows the Build and run steps on a clean checkout ends up with a missing stimulus file. The sentence that is left at line 38 also has no verb ("... `ready_to_drive.json` hand-maintained FIL networks."). Bring back the prerequisite and fix the sentence.

</details>

</details>

</details>

<details>
<summary><b>Verification</b></summary>

<b>Rules</b> <kbd>No rules evaluated</kbd>

<details>
<summary><b>Functional validation</b> <kbd>Not enabled</kbd></summary>

[Set up](https://docs.gitar.ai/features/functional-validation)

</details>

<sub>For more verification details, comment `gitar display:verbose`.</sub>

</details>

<details>
<summary><b>Options</b> </summary>

<kbd>Auto-apply is off</kbd> → Gitar will not commit updates to this branch.<br><kbd>Display: compact</kbd> → Showing compact verification results.

Comment with these commands to change the behavior for this request:

<table>
<tr>
<td><kbd>Auto-apply</kbd></td>
<td><kbd>Compact</kbd></td>
</tr>
<tr>
<td>

```
gitar auto-apply:on         
```
</td>
<td>

```
gitar display:verbose         
```
</td>
</tr>
</table>

</details>

<sub>Was this helpful? React with 👍 / 👎 | Powered by [Gitar](https://gitar.ai) — free for open source</sub>
