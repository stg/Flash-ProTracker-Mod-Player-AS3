/*
	This work is published under the Creative Commons BY-NC license available at:
	http://creativecommons.org/licenses/by-nc/3.0/
	
	Author: senseitg@gmail.com
	
	Contact the author for commercial licensing information.
	
	stg.mod.player
		player( data:ByteArray, samples:Sound = null )
		play()
		stop()
		isPlaying:Boolean
		preLoad( time:Number = 0 )
		preLoaded:int
		soundTransform:SoundTransform
		
	
	Allows playback of nearly all ProTracker Modules.
	
	All effects are implemented and tested, except for FunkRepeat/Invert Loop.
	
	Capable of realtime playback as well as preloading into a sample buffer for less
	CPU intense playback. Playback can be performed while preloading.
	
	Preloading requires a significant amount of memory and is not recommended for long musics.
	
	Modules may be split into a data and audio section by using an external program.
	This allows flash to MP3-compress the sample data as a Sound-object that is passed
	when initializing the player. For some modules, this saves a significant amount of
	space - without seriously compromising the audio quality.
*/
package stg.mod {
	
	import flash.events.*;
	import flash.utils.*;
	import flash.media.*;
	
	/*
	This file contains two currently unused and commented out features:
	   3-cell coding
	     A method to reduce pattern sizes by 25%
	   Sample correction
	     A method to correct for intersample glitches caused by MP3-encoding
	
	Both features are experimental and may become available in future versions.
	They cannot currently be used because they require changes to the module splitter.
	*/
		
	public class player {

		/* Public interface */
		
		public var soundTransform:SoundTransform = null;

		// Initializer
		// @data ProTracker module in ByteArray
		// @samples For modules split into data/mp3 compressed samples section, pass the samples
		//          Sound object to be used to reconstruct the sample data, else omitted/null.
		public function player( data:ByteArray, samples:Sound = null ) {
			var tempArray:ByteArray, skipsz:int;
			mod_data = data;
			if( samples != null ) {
				tempArray = new ByteArray();
				samples.extract( tempArray, samples.length * 50 );
				tempArray.position = 0;
				mod_data.position = mod_data.length;
				tempArray.readFloat();
				// Skip data size
				// Depends on how you've imported your samples
				// Data is always extracted as 44kHz stereo, so for:
				// 11kHz samples: * 7
				// 22kHz samples: * 3
				// 44kHz samples: * 1
				skipsz = tempArray.position * 7; // 11kHz
				tempArray.position = 0;
				while( tempArray.position < tempArray.length ) {
					mod_data.writeByte( tempArray.readFloat() * 127 );
					tempArray.position += skipsz;
				}
			}
			mod_data.position = 0;
			mod_split = ( samples != null );
			load_module();
		}
		
		// (Re)starts playback
		public function play() {
			mod_sound = new Sound();
			mod_sound.addEventListener( SampleDataEvent.SAMPLE_DATA, realtime_samples );
			mod_channel = mod_sound.play();
			if( soundTransform ) mod_channel.soundTransform = soundTransform;
		}
		
		// Pauses playback
		public function stop() {
			mod_sound.removeEventListener( SampleDataEvent.SAMPLE_DATA, realtime_samples );
			mod_sound = null;
		}
		
		// Returns true if module is currently playing
		public function get isPlaying():Boolean {
			return( mod_sound != null );
		}

		// Preloads samples for later playback using minimum CPU time.
		// @time Number of milliseconds before returning
		public function preLoad( time:Number = 0 ) {
			var temp:int, start:Number, pos:int;
			start = getTimer();
			if( audio_data == null ) {
				audio_data = new ByteArray();
				for( temp = 0; temp < 128; temp++ ) audio_data_order[ temp ] = 0;
			}
			pos = audio_data.position;
			audio_data.position = audio_data.length;
			while( 1 ) {
				if( ctr-- == 0 ) {
					ctr = cia;
					temp = ix_order;
					play_module();
					if( temp != ix_order ) {
						if( pregen_break ) {
							audio_data_loop = audio_data_order[ ix_order ];
							audio_data.position = pos;
							mod_data = null;
							audio_data_order = null;
							return( true );
						}
						if( ix_order == 0 || audio_data_order[ ix_order ] != 0 ) {
							pregen_break = true;
						} else {
							audio_data_order[ ix_order ] = audio_data.length;
						}
					}
					if( time > 0 && getTimer() - start > time ) break;
				}
				write_sample( audio_data );
			}
			
			audio_data.position = pos;
			return( false );
		}

		public function get preLoaded():int {
			return( audio_data.length );
		}

		/* Private variables */

		private var mod_data:ByteArray;
		private var mod_sound:Sound;
		private var mod_channel:SoundChannel;
		private var mod_split = false;
		private var loaded:Boolean = false;
		private var speed:int = 6;
		private var tick:int = 0;
		private var ix_nextrow:int = 0;
		private var ix_nextorder:int = 0;
		private var ix_row:int = 0;
		private var ix_order:int = 0;
		private var delay:int = 0;
		private var fxm:Array = [ new fxm_t(), new fxm_t(), new fxm_t(), new fxm_t() ]
		private var dma:Array = [ new dma_t(), new dma_t(), new dma_t(), new dma_t() ]
		private var sample:Array = new Array();
		private var order_count:int = 0;
		private var p_audio_ram:int, p_ptn_ram:int, p_order_ram:int;
		private var ctr:int = 0;
		private var cia:int = 882;
		private var audio_data:ByteArray = null;
		private var audio_data_loop:int = 0;
		private var audio_data_order:Array = new Array();
		private var pregen_break:Boolean = false;
		
		// Sample correction
		//private static const sample_correction = 0;
		
		// Amiga period base frequency ( video_clock / ( 44100 * 2 ) )
		// PAL video clock: 7093789.2
		// NTSC video clock: 7159090.5
		private static const sys_freq = 80.42844897959184; // PAL
		//private static const sys_freq = 81.16882653061224; // NTSC
		
		// ProTracker period tables for each finetune value
		private static const period_tbl = [
			[ 856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453, 428, 404, 381, 360, 339, 320,
			  302, 285, 269, 254, 240, 226, 214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113 ],
			[ 850, 802, 757, 715, 674, 637, 601, 567, 535, 505, 477, 450, 425, 401, 379, 357, 337, 318, 
			  300, 284, 268, 253, 239, 225, 213, 201, 189, 179, 169, 159, 150, 142, 134, 126, 119, 113 ],
			[ 844, 796, 752, 709, 670, 632, 597, 563, 532, 502, 474, 447, 422, 398, 376, 355, 335, 316,
			  298, 282, 266, 251, 237, 224, 211, 199, 188, 177, 167, 158, 149, 141, 133, 125, 118, 112 ],
			[ 838, 791, 746, 704, 665, 628, 592, 559, 528, 498, 470, 444, 419, 395, 373, 352, 332, 314,
			  296, 280, 264, 249, 235, 222, 209, 198, 187, 176, 166, 157, 148, 140, 132, 125, 118, 111 ],
			[ 832, 785, 741, 699, 660, 623, 588, 555, 524, 495, 467, 441, 416, 392, 370, 350, 330, 312,
			  294, 278, 262, 247, 233, 220, 208, 196, 185, 175, 165, 156, 147, 139, 131, 124, 117, 110 ],
			[ 826, 779, 736, 694, 655, 619, 584, 551, 520, 491, 463, 437, 413, 390, 368, 347, 328, 309,
			  292, 276, 260, 245, 232, 219, 206, 195, 184, 174, 164, 155, 146, 138, 130, 123, 116, 109 ],
			[ 820, 774, 730, 689, 651, 614, 580, 547, 516, 487, 460, 434, 410, 387, 365, 345, 325, 307,
			  290, 274, 258, 244, 230, 217, 205, 193, 183, 172, 163, 154, 145, 137, 129, 122, 115, 109 ],
			[ 814, 768, 725, 684, 646, 610, 575, 543, 513, 484, 457, 431, 407, 384, 363, 342, 323, 305,
			  288, 272, 256, 242, 228, 216, 204, 192, 181, 171, 161, 152, 144, 136, 128, 121, 114, 108 ],
			[ 907, 856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453, 428, 404, 381, 360, 339,
			  320, 302, 285, 269, 254, 240, 226, 214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120 ],
			[ 900, 850, 802, 757, 715, 675, 636, 601, 567, 535, 505, 477, 450, 425, 401, 379, 357, 337,
			  318, 300, 284, 268, 253, 238, 225, 212, 200, 189, 179, 169, 159, 150, 142, 134, 126, 119 ],
			[ 894, 844, 796, 752, 709, 670, 632, 597, 563, 532, 502, 474, 447, 422, 398, 376, 355, 335,
			  316, 298, 282, 266, 251, 237, 223, 211, 199, 188, 177, 167, 158, 149, 141, 133, 125, 118 ],
			[ 887, 838, 791, 746, 704, 665, 628, 592, 559, 528, 498, 470, 444, 419, 395, 373, 352, 332,
			  314, 296, 280, 264, 249, 235, 222, 209, 198, 187, 176, 166, 157, 148, 140, 132, 125, 118 ],
			[ 881, 832, 785, 741, 699, 660, 623, 588, 555, 524, 494, 467, 441, 416, 392, 370, 350, 330,
			  312, 294, 278, 262, 247, 233, 220, 208, 196, 185, 175, 165, 156, 147, 139, 131, 123, 117 ],
			[ 875, 826, 779, 736, 694, 655, 619, 584, 551, 520, 491, 463, 437, 413, 390, 368, 347, 328,
			  309, 292, 276, 260, 245, 232, 219, 206, 195, 184, 174, 164, 155, 146, 138, 130, 123, 116 ],
			[ 868, 820, 774, 730, 689, 651, 614, 580, 547, 516, 487, 460, 434, 410, 387, 365, 345, 325,
			  307, 290, 274, 258, 244, 230, 217, 205, 193, 183, 172, 163, 154, 145, 137, 129, 122, 115 ],
			[ 862, 814, 768, 725, 684, 646, 610, 575, 543, 513, 484, 457, 431, 407, 384, 363, 342, 323,
			  305, 288, 272, 256, 242, 228, 216, 203, 192, 181, 171, 161, 152, 144, 136, 128, 121, 114 ]
		]

		// ProTracker sine table, could be replaced by realtime Math.sin( n * Math.PI / 32 )
		private static const sine = [
			0x00, 0x0C, 0x18, 0x25, 0x30, 0x3C, 0x47, 0x51, 0x5A, 0x62, 0x6A, 0x70, 0x76, 0x7A, 0x7D, 0x7F,
			0x7F, 0x7F, 0x7D, 0x7A, 0x76, 0x70, 0x6A, 0x62, 0x5A, 0x51, 0x47, 0x3C, 0x30, 0x25, 0x18, 0x0C,
			0x00, 0xF3, 0xE7, 0xDA, 0xCF, 0xC3, 0xB8, 0xAE, 0xA5, 0x9D, 0x95, 0x8F, 0x89, 0x85, 0x82, 0x80,
			0x80, 0x80, 0x82, 0x85, 0x89, 0x8F, 0x95, 0x9D, 0xA5, 0xAE, 0xB8, 0xC3, 0xCF, 0xDA, 0xE7, 0xF3
		];

		// Look up or generate waveform for ProTracker vibrato/tremolo oscillator
		private function do_osc( p_osc:osc_t ):int {
			var sample:int = 0;
			var mul:int;
			
			switch( p_osc.mode & 0x03 ) {
				case 0: // Sine
					sample = sine[ ( p_osc.offset ) & 0x3F ];
					if( sample > 127 ) sample -= 256;
					break;
				case 1: // Square
					sample = ( p_osc.offset & 0x20 ) ? 127 : -128;
					break;
				case 2: // Saw
					sample = ( ( p_osc.offset << 2 ) & 0xFF ) - 128;
					break;
				case 3: // Noise (random)
					sample = Math.floor( Math.random() * 256 ) - 128;
					break;
			}
			mul = sample * lo4( p_osc.fxp );
			p_osc.offset = ( p_osc.offset + hi4( p_osc.fxp ) - 1 ) & 0xFF;
			return( mul / 64 );

		}
		
		// Calculates and returns arpeggio period
		private function arpeggio( ch:int, halftones:int ):int {
			var n:int, tuning:int = sample[ fxm[ ch ].sample ].tuning;
			// Find base note
			for( n = 0; n != 35; n++ ) {
				if( fxm[ ch ].period >= period_tbl[ tuning ][ n ] ) break;
			}
			trace( fxm[ch].period, n );
			// Clamp and return arpeggio period
			return( period_tbl[ tuning ][ Math.min( n + halftones, 35 ) ] );
		}
		
		// Calculates and returns glissando period
		private function glissando( ch:int ):int {
			var n:int, tuning:int = sample[ fxm[ ch ].sample ].tuning;
			// Round off to nearest note period
			for( n = 0; n != 35; n++ ) {
				if( fxm[ ch ].period < period_tbl[ tuning ][ n ] &&
				    fxm[ ch ].period >= period_tbl[ tuning ][ n + 1 ] ) {
					if( period_tbl[ tuning ][ n ] - fxm[ ch ].period > fxm[ ch ].period - period_tbl[ tuning ][ n + 1 ] ) n++
					break;
				}
			}
			// Clamp and return arpeggio period
			return( period_tbl[ tuning ][ n ] );
		}

		// Sets up and starts a DMA channel
		private function note_start( p_dma:dma_t, ix_sample:int, period:int, offset:int ) {
			// Set address points
			p_dma.pa        = sample[ ix_sample ].dma_pa + ( offset << 8 );
			p_dma.pb        = sample[ ix_sample ].dma_pb;
			p_dma.pc        = sample[ ix_sample ].dma_pc;
			// Set reload register (defines rate)
			p_dma.rate      = sys_freq / period_tbl[ sample[ ix_sample ].tuning ][ period ];
			// Set mode (begin playback)
			p_dma.loop      = sample[ ix_sample ].loop;
			p_dma.active    = true;
			p_dma.addr      = p_dma.pa;
			// Set loop-point
			p_dma.pa        = sample[ ix_sample ].dma_pd;
		}
		
		// Generates realtime sample data, using either realtime
		// hardware emulation or the preloaded sample buffer
		private function realtime_samples( e:SampleDataEvent ) {
			var i:int;
			if( audio_data == null ) {
				for( i = 0; i < 2048; i++ ) {
					if( ctr-- == 0 ) {
						ctr = cia;
						play_module();
					}
					write_sample( e.data );
				}
			} else {
				for( i = 0; i < 2048; i++ ) {
					if( audio_data.position >= audio_data.length ) audio_data.position = audio_data_loop;
					e.data.writeFloat( audio_data.readFloat() );
					e.data.writeFloat( audio_data.readFloat() );
				}
			}
		}
		
		// Processed DMA channels and writes a single stereo sample
		// Could be converted to inline for a small performance boost
		// Supports interpolated and non-interpolated sample models
		private function write_sample( data:ByteArray ) {
			var ch:int = 0, p_dma:dma_t;
			var left:Number = 0, right:Number = 0;
			//var temp:int; // Required for interpolated version
			while( ch != 4 ) {
				
				// Emulate hardware DMA channels
				p_dma = dma[ ch++ ];
				if( p_dma.active ) {
					p_dma.addr += p_dma.rate;
					if( p_dma.addr >= p_dma.pb ) {
						if( p_dma.loop ) {
							p_dma.addr += p_dma.pa - p_dma.pb;
							p_dma.pb = p_dma.pc;
						} else {
							p_dma.addr = p_dma.pb - 1;
							p_dma.active = false;
						}
					}
				}
				
				/* With interpolation
				temp = Math.floor( p_dma.addr );
				p_dma.lastsample = p_dma.newsample;
				mod_data.position = temp + p_audio_ram;
				p_dma.newsample = mod_data.readByte();
				if( ch == 0 || ch == 3 ) {
					left += ( p_dma.lastsample * ( 1 - p_dma.fract ) + p_dma.newsample * p_dma.fract ) * p_dma.volume;
				} else {
					right += ( p_dma.lastsample * ( 1 - p_dma.fract ) + p_dma.newsample * p_dma.fract ) * p_dma.volume;
				}
				p_dma.fract = p_dma.addr - temp;
				*/

				/* Without interpolation */
				mod_data.position = int( p_dma.addr ) + p_audio_ram;
				if( ch == 0 || ch == 3 ) {
					left += mod_data.readByte() * p_dma.volume;
				} else {
					right += mod_data.readByte() * p_dma.volume;
				}
			}
			data.writeFloat( left / 16384 );
			data.writeFloat( right / 16384 );
		}
		
		// Returns the high nibble of a byte
		private function hi4( v:int ):int {
			return( ( v >> 4 ) & 0x0F );
		}

		// Returns the low nibble of a byte
		private function lo4( v:int ):int {
			return( v & 0x0F );
		}

		// Deconstructs a ProTracker module into a more manageable memory model
		private function load_module() {
			var n:int, z:int, row:int, ch:int;
			var temp_b:int, temp_w:int;
			var p_sample:sample_t;
			var loop_offset:int, loop_len:int;
			var p_ptn:pattern_t = new pattern_t();
			var patterns:int;
			mod_data.endian = Endian.BIG_ENDIAN;
			if( !mod_split )mod_data.position += 20;				// Skip song title
			
			// Read samples
			p_audio_ram = 0;
			for( n = 0; n != 31; n++ ) {
				p_sample = new sample_t();
				if( !mod_split )mod_data.position += 22;			// Skip sample name
				p_sample.dma_pa = p_audio_ram;						// Set sample starting address
				p_sample.len = mod_data.readUnsignedShort() << 1;	// Get length
				if( p_sample.len || !mod_split ) {
					p_sample.tuning = mod_data.readUnsignedByte();		// Get finetune value
					p_sample.dma_volume = mod_data.readUnsignedByte();	// Get volume
					loop_offset = mod_data.readUnsignedShort() << 1;	// Get loop start
					loop_len = mod_data.readUnsignedShort() << 1;		// Get loop length
				}
				p_sample.dma_pb   = p_audio_ram + p_sample.len;
				p_sample.dma_pd   = ( loop_len < 3 ? 0 : loop_offset ) + p_sample.dma_pa;
				p_sample.dma_pc   = ( loop_len < 3 ? p_sample.dma_pb : p_sample.dma_pd + loop_len );
				p_sample.loop     = loop_len >= 3;
				p_audio_ram       += p_sample.len;
				/* Sample correction
				if( mod_split && p_sample.len ) {
					p_audio_ram += sample_correction;
					if( loop_len ) {
						if( loop_offset < sample_correction ) {
							temp_b = sample_correction - loop_offset;
							p_audio_ram += temp_b;
							p_sample.dma_pa += temp_b;
							p_sample.dma_pb += temp_b;						
							p_sample.dma_pc += temp_b;
							p_sample.dma_pd += temp_b;
						}
					} else {
						p_sample.dma_pa += sample_correction / 2;
						p_sample.dma_pb += sample_correction / 2;
					}
				}
				*/				
				sample[ n ] = p_sample;
			}

			// Read orders and counts
			order_count = mod_data.readUnsignedByte();				// Read order order count
			if( !mod_split ) mod_data.position++;					// Skip repeat/tracker id
			p_order_ram = mod_data.position;
			for( n = 0; n < ( mod_split ? order_count : 128 ); n++ ) {
				temp_b = mod_data.readUnsignedByte()
				if( temp_b >= patterns ) patterns = temp_b + 1;
			}

			// Read patterns
			/* 3-cell coding
			if( mod_split ) {
				p_ptn_ram = mod_data.position;
				mod_data.position += patterns * 768;
			} else {
			*/
				if( !mod_split ) mod_data.position += 4;				// Skip tracker ID
				p_ptn_ram = mod_data.position;
				for( n = 0; n < patterns * 256; n++ ) {
					temp_b = mod_data.readUnsignedByte();				// Deconstruct sample.msb and period.msb
					temp_w = ( temp_b & 0x0F ) << 8;
					p_ptn.sample = temp_b & 0xF0;
					temp_b = mod_data.readUnsignedByte();				// Deconstruct period.lsb
					temp_w |= temp_b;
					temp_b = mod_data.readUnsignedByte();				// Deconstruct sample.lsb and effect
					p_ptn.sample |= hi4( temp_b );
					p_ptn.effect = lo4( temp_b ) << 4;
					p_ptn.param = mod_data.readUnsignedByte();			// Deconstruct parameters
					if( p_ptn.effect == 0xE0 ) {
						p_ptn.effect |= hi4( p_ptn.param );
						p_ptn.param &= 0x0F;
					}
					p_ptn.ix_period = 0x7F;								// Find note index from period
					if( temp_w ) {
						for( z = 0; z != 36; z++ ) {
							if( period_tbl[ 0 ][ z ] == temp_w ) {
								p_ptn.ix_period = z;					// Note index found
								break;
							}
						}
						if( z == 36 ) {
							trace( 'Not a ProTracker MOD!' );
							return;
						}
					}
					/* 3-cell coding
					mod_data.position -= 4;
					mod_data.writeByte( p_ptn.effect | ( p_ptn.param >> 4 ) );
					mod_data.writeByte( ( ( p_ptn.param & 0x0F ) << 4 ) | ( p_ptn.sample >> 1 ) );
					mod_data.writeByte( ( p_ptn.sample << 7 ) | p_ptn.ix_period );
					mod_data.writeByte( 0 );
					// else... */
					mod_data.position -= 4;
					mod_data.writeByte( p_ptn.ix_period );
					mod_data.writeByte( p_ptn.sample );
					mod_data.writeByte( p_ptn.effect );
					mod_data.writeByte( p_ptn.param );
				}
			//}
			p_audio_ram = mod_data.position;
			
			// Correct a common error: sample data outside of mod length
			for( n = 0; n < 31; n++ ) {
				p_sample = sample[ n ];
				if( p_sample.dma_pa + p_audio_ram >= mod_data.length ) p_sample.dma_pa = mod_data.length - p_audio_ram - 1;
				if( p_sample.dma_pd + p_audio_ram >= mod_data.length ) p_sample.dma_pd = mod_data.length - p_audio_ram - 1;
				if( p_sample.dma_pb + p_audio_ram > mod_data.length ) p_sample.dma_pb = mod_data.length - p_audio_ram;
				if( p_sample.dma_pc + p_audio_ram > mod_data.length ) p_sample.dma_pc = mod_data.length - p_audio_ram;
			}

			// All good
			loaded = true;
		}
		
		// Progress module by one tick
		function play_module() {
			var ch:int, fx:int, fxp:int;
			var temp:int;
			var p_ptn:pattern_t = new pattern_t;
			var p_fxm:fxm_t;
			var p_dma:dma_t;
			
			// Abort if no module is loaded
			if( !loaded ) return;
			
			// Advance tick
			if( ++tick == speed ) tick = 0;
			
			// Handle row delay
			if( delay ) {
				if( tick == 0 ) delay--;
				return;
			}
			
			// Advance playback
			if( tick == 0 ) {
				if( ++ix_row == 64 ) {
					ix_row = 0;
					if( ++ix_order == order_count ) ix_order = 0;
				}
			
				// Forced order/row
				if( ix_nextorder != 0xFF ) {
					ix_order = ix_nextorder;
					ix_nextorder = 0xFF;
				}
				if( ix_nextrow != 0xFF ) {
					ix_row = ix_nextrow;
					ix_nextrow = 0xFF;
				}
			
			}

			// Point to first channel in current cell
			mod_data.position = p_order_ram + ix_order;
			mod_data.position = p_ptn_ram + ( ( mod_data.readUnsignedByte() * 64 ) + ix_row ) * 16; // ( mod_split ? 12 : 16 ); // 3-cell coding

			for( ch = 0; ch != 4; ch++ ) {
				
				/* 3-cell coding
				p_ptn.effect = mod_data.readUnsignedByte();
				p_ptn.param = 0x00;
				if( ( p_ptn.effect & 0xF0 ) != 0xE0 ) {
					p_ptn.param  = ( p_ptn.effect << 4 ) & 0xF0;
					p_ptn.effect = p_ptn.effect & 0xF0;
				}
				p_ptn.sample    = mod_data.readUnsignedByte();
				p_ptn.param     = p_ptn.param | ( p_ptn.sample >> 4 );
				p_ptn.sample    = ( p_ptn.sample << 1 ) & 0x1F;
				p_ptn.ix_period = mod_data.readUnsignedByte();
				p_ptn.sample    = p_ptn.sample | ( p_ptn.ix_period >> 7 );
				p_ptn.ix_period = p_ptn.ix_period & 0x7F;
				if( !mod_split ) mod_data.readUnsignedByte();
				// else... */
				p_ptn.ix_period = mod_data.readUnsignedByte();
				p_ptn.sample = mod_data.readUnsignedByte();
				p_ptn.effect = mod_data.readUnsignedByte();
				p_ptn.param = mod_data.readUnsignedByte();
					
				p_fxm = fxm[ ch ];
				p_dma = dma[ ch ];
			
				// Quick access to effect and parameters speeds up code
				fx  = p_ptn.effect;
				fxp = p_ptn.param;
				
				if( tick == 0 ) {
					
					// Set tuning
					if( fx == 0xE5 ) sample[ p_fxm.sample ].tuning = fxp;

					if( p_ptn.sample != 0 ) {
						// Cell has sample
						temp = p_ptn.sample - 1;
						p_fxm.sample = temp;
						p_fxm.volume = sample[ temp ].dma_volume;
						// Reset volume unless delayed
						if( fx != 0xED || fxp== 0x00 ) p_dma.volume = sample[ temp ].dma_volume;
						// Re-trigger oscillator offsets
						if( ( p_fxm.vibr.mode & 0x4 ) == 0x0 ) p_fxm.vibr.offset = 0;
						if( ( p_fxm.trem.mode & 0x4 ) == 0x0 ) p_fxm.trem.offset = 0;
					}
					
					if( p_ptn.ix_period != 0x7F ) {
						// Cell has note
						if( fx == 0x30 || fx == 0x50 ) {
							// Tone-portamento effect setup
							p_fxm.port_target = period_tbl[ sample[ p_ptn.sample ].tuning ][ p_ptn.ix_period ];
						} else {
							// Start note unless delayed
							temp = p_fxm.sample;
							if( fx != 0xED || fxp== 0x00 ) note_start( p_dma, temp, p_ptn.ix_period, ( fx == 0x90 ? fxp : 0 ) );
							// Set required effect memory parameters
							p_fxm.period = period_tbl[ sample[ temp ].tuning ][ p_ptn.ix_period ];
						}
					}
					
					// Effects processed when tick = 0
					switch( fx ) {
						case 0x30: // Portamento
							if( fxp ) p_fxm.port_speed = fxp;
							break;
						case 0xB0: // Jump to pattern
							ix_nextorder = ( fxp >= order_count ? 0x00 : fxp );
							ix_nextrow = 0;
							break;
						case 0xC0: // Set volume
							p_fxm.volume = Math.min( fxp, 0x40 );
							p_dma.volume = p_fxm.volume;
							break;
						case 0xD0: // Jump to row
							fxp = hi4( fxp ) * 10 + lo4( fxp );
							ix_nextorder = ( ix_order + 1 >= order_count ? 0x00 : ix_order + 1 );
							ix_nextrow = ( fxp > 63 ? 0 : fxp );
							break;
						case 0xF0: // Set speed
							if( fxp > 0x20 ) {
								cia = 44100 / ( ( 24 * fxp ) / 60 );
							} else {
								speed = fxp;
							}
							break;
						case 0x40: // Vibrato
							if( fxp ) p_fxm.vibr.fxp = fxp;
							break;
						case 0xE1: // Fine slide up
							p_fxm.period = Math.max( p_fxm.period - fxp, 113 );
							p_dma.rate = sys_freq / p_fxm.period;
							break;
						case 0xE2: // Fine slide down
							p_fxm.period = Math.min( p_fxm.period + fxp, 856 );
							p_dma.rate = sys_freq / p_fxm.period;
							break;
						case 0xE3: // Glissando control
							p_fxm.glissando = ( fxp != 0 );
							break;
						case 0xE4: // Set vibrato waveform
							p_fxm.vibr.mode = fxp;
							break;
						case 0xE6: // Loop-back (advanced looping)
							if( fxp == 0x0 ) {
								p_fxm.loop_order = ix_order;
								p_fxm.loop_row   = ix_row;
							} else {
								p_fxm.loop_count = ( p_fxm.loop_count ? p_fxm.loop_count - 1 : fxp );
								if( p_fxm.loop_count ) {
									ix_nextorder = p_fxm.loop_order;
									ix_nextrow   = p_fxm.loop_row;
								}
							}
							break;
						case 0xE7: // Set tremolo waveform
							p_fxm.trem.mode = fxp;
							break;
						case 0xEA: // Fine volume slide up
							p_fxm.volume = Math.min( p_fxm.volume + fxp, 0x40 );
							p_dma.volume = p_fxm.volume;
							break;
						case 0xEB: // Fine volume slide down
							p_fxm.volume = Math.max( p_fxm.volume - fxp, 0 );
							p_dma.volume = p_fxm.volume;
							break;
						case 0xEE: // Delay
							delay = fxp;
							break;
					}
					
				} else {
					// Effects processed when tick > 0
					switch( fx ) {
						case 0x10: // Slide up
							p_fxm.period = Math.max( p_fxm.period - fxp, 113 );
							p_dma.rate = sys_freq / p_fxm.period;
							break;
						case 0x20: // Slide down
							p_fxm.period = Math.min( p_fxm.period + fxp, 856 );
							p_dma.rate = sys_freq / p_fxm.period;
							break;
						case 0xE9: // Retrigger note
							temp = tick; while( temp >= fxp ) temp -= fxp;
							if( temp == 0 ) note_start( p_dma, p_fxm.sample, p_ptn.ix_period, ( fx == 0x90 ? fxp : 0 ) );
							break;
						case 0xEC: // Note cut
							if( fxp == tick ) p_dma.volume = 0x00;
							break;
						case 0xED: // Delayed note
							if( fxp == tick ) {
								if( p_ptn.sample ) p_dma.volume = sample[ p_fxm.sample ].dma_volume;
								if( p_ptn.ix_period != 0x7F ) note_start( p_dma, p_fxm.sample, p_ptn.ix_period, ( fx == 0x90 ? fxp : 0 ) );
							}
							break;
						default:   // Multi-effect processing
							// Portamento
							if( fx == 0x30 || fx == 0x50 ) {
								if( p_fxm.period < p_fxm.port_target ) p_fxm.period = Math.min( p_fxm.period + p_fxm.port_speed,  p_fxm.port_target );
								else                                   p_fxm.period = Math.max( p_fxm.period - p_fxm.port_speed,  p_fxm.port_target );
								if( p_fxm.glissando ) p_dma.rate = sys_freq / glissando( ch );
								else                  p_dma.rate = sys_freq / p_fxm.period;
							}
							// Volume slide
							if( fx == 0x50 || fx == 0x60 || fx == 0xA0 ) {
								if( ( fxp & 0xF0 ) == 0 ) p_fxm.volume -= ( lo4( fxp ) );
								if( ( fxp & 0x0F ) == 0 ) p_fxm.volume += ( hi4( fxp ) );
								p_fxm.volume = Math.max( Math.min( p_fxm.volume, 0x40 ), 0 )
								p_dma.volume = p_fxm.volume;
							}
					}
				}
					
				// Normal play and arpeggio
				if( fx == 0x00 ) {
					temp = tick; while( temp > 2 ) temp -= 2;
					if( temp == 0 ) {
						// Reset
						p_dma.rate = sys_freq / p_fxm.period;
					} else if( fxp ) {
						// Arpeggio
						p_dma.rate = sys_freq / arpeggio( ch, ( temp == 1 ? hi4( fxp ) : lo4( fxp ) ) );
					}
				} else if( fx == 0x40 || fx == 0x60 ) {
					// Vibrato
					p_dma.rate = sys_freq / ( p_fxm.period + do_osc( p_fxm.vibr ) );
				} else if( fx == 0x70 ) {
					// Tremolo
					temp = p_fxm.volume + do_osc( p_fxm.trem );
					p_dma.volume = Math.max( Math.min( temp, 0x40 ), 0 )
				}
				
			}
		}
	}
}

// ProTracker oscillator (tremolo and vibrator)
class osc_t {
	public var fxp:int = 0;					// Effect parameter (speed/depth)
	public var offset:int = 0;				// Offset
	public var mode:int = 0;				// Mode (waveform type)
}

// Effect memory
class fxm_t {
	public var sample:int = 0;				// Sample number
	public var volume:int = 0;				// Volume
	public var port_speed:int = 0;			// Portamento speed
	public var port_target:int = 0;			// Portamento target
	public var glissando:Boolean = false;	// Glissando
	public var vibr:osc_t = new osc_t();	// Vibrato oscillator
	public var trem:osc_t = new osc_t();	// Tremolo oscillator
	public var period:int = 0;				// Period (amiga frequency)
	public var loop_order:int = 0;			// Advanced looping order
	public var loop_row:int = 0;			// Advanced looping row
	public var loop_count:int = 0;			// Advanced looping counter
}

// Sample descriptor
class sample_t {
	public var dma_pa:int;					// Ram point A (start of sample)
	public var dma_pb:int;					// Ram point B (end of first run)
	public var dma_pc:int;					// Ram point C (end of loop)
	public var dma_pd:int;					// Ram point D (start of loop)
	public var loop:Boolean;				// Loop the sample
	public var dma_volume:int;				// Default volume
	public var tuning:int;					// Tuning parameter (see period_tbl)
	public var len:int;						// Sample length
}

// Pattern cell
class pattern_t {
	public var ix_period:int;				// Index into period table
	public var sample:int;					// Sample number
	public var effect:int;					// Effect type
	public var param:int;					// Effect parameters
}

// DMA registers for hardware emulation
class dma_t {
	public var pa:int = 0;					// Point A (start)
	public var pb:int = 0;					// Point B (end)
	public var pc:int = 0;					// Point C (pb reload @end)
	public var active:Boolean = false;		// Channel is playing
	public var loop:Boolean = false;		// Loop when reached point B
	public var rate:Number = 0;				// Rate/frequency
	public var volume:int = 0;				// Volume
	public var addr:Number = 0;				// Current address (fractional)
	/* Required for interpolation
	public var fract:Number = 0;			// Address fraction for interpolation
	public var lastsample:Number = 0;		// Previous sample for interpolation
	public var newsample:Number = 0;		// Current sample for interpolation
	*/
}