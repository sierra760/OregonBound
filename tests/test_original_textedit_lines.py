from pathlib import Path
import hashlib
import json
from capstone import Cs, CS_ARCH_M68K, CS_MODE_BIG_ENDIAN, CS_MODE_M68K_000
from macresources.greggybits import unpack

ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / 'raw/system7'


def ops(data, start, end):
    md = Cs(CS_ARCH_M68K, CS_MODE_BIG_ENDIAN | CS_MODE_M68K_000)
    return {i.address: (i.mnemonic, i.op_str) for i in md.disasm(data[start:end], start)}


def textedit():
    return (FOLDER / 'textedit_lpch_15_unpacked.bin').read_bytes()


def test_preserved_original_system_resources_match_provenance():
    manifest = json.loads((FOLDER / 'textedit_provenance.json').read_text())
    assert manifest['source_disk_sha256'] == '691e76c73a88cd04ced93ec2c84661ca4d900581790e65188ce495f381b005b1'
    for resource in manifest['resources']:
        packed = (FOLDER / resource['compressed_file']).read_bytes()
        code = (FOLDER / resource['unpacked_file']).read_bytes()
        assert unpack(packed) == code
        assert hashlib.sha256(packed).hexdigest() == resource['compressed_sha256']
        assert hashlib.sha256(code).hexdigest() == resource['unpacked_sha256']


def test_roman_line_width_has_no_caret_subtraction_and_breaks_at_cr_only():
    code = textedit()
    assert list(ops(code, 0x2814, 0x2822).values()) == [
        ('moveq', '#$0, d4'), ('move.w', '$6(a3), d4'),
        ('sub.w', '$2(a3), d4'), ('move.l', 'd4, -$8(a6)')]
    assert ops(code, 0xa74, 0xa7a)[0xa74] == ('cmpi.b', '#$d, d0')
    branch = ops(code, 0x2932, 0x2960)
    assert branch[0x2932] == ('tst.b', 'd0') # Literal low-byte quirk.
    assert branch[0x295c] == ('beq.b', '$29ac') # CR ends whitespace lookahead.
    assert ops(code, 0x25fe, 0x2610)[0x2604] == ('cmpi.b', '#$20, (a0, d0.l)')


def test_exact_edge_hits_back_off_character_before_word_scan():
    roman = (FOLDER / 'roman_text_ptch_27_unpacked.bin').read_bytes()
    pixel = ops(roman, 0xac2, 0xae6)
    assert pixel[0xac8] == ('blt.b', '$aac') # Continue measuring only while < width.
    assert pixel[0xad2] == ('blt.w', '$b10') # End-of-text uses the same strict edge.
    assert pixel[0xade] == ('bhi.b', '$ae6') # Choose hit side by midpoint.
    assert pixel[0xae4] == ('subq.w', '#$1, d4') # Leading side returns prior offset.
    te = ops(textedit(), 0x89c, 0x8cc)
    assert te[0x8a4] == ('bne.b', '$8cc') # Leading side already backed off.
    assert te[0x8bc] == ('move.w', '#$ffff, d3') # Trailing side also backs off.


def test_nlines_counts_terminated_lines_without_trailing_empty_line():
    code = textedit()
    setup = ops(code, 0x29e0, 0x29fc)
    assert setup[0x29e6] == ('clr.w', '$5e(a3)')
    assert setup[0x29f8] == ('beq.w', '$2a7e') # Empty text exits with zero.
    loop = ops(code, 0x2b60, 0x2b70)
    assert loop[0x2b64] == ('addq.w', '#$1, $5e(a3)')
    assert loop[0x2b6a] == ('cmp.w', '$3c(a3), d6')
    assert loop[0x2b6e] == ('bcs.b', '$2b82') # No next line when end == teLength.
