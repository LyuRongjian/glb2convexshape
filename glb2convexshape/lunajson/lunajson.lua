local newdecoder = require 'glb2convexshape.lunajson.decoder'
local newencoder = require 'glb2convexshape.lunajson.encoder'
local sax = require 'glb2convexshape.lunajson.sax'
-- If you need multiple contexts of decoder and/or encoder,
-- you can require lunajson.decoder and/or lunajson.encoder directly.
return {
	decode = newdecoder(),
	encode = newencoder(),
	newparser = sax.newparser,
	newfileparser = sax.newfileparser,
}
