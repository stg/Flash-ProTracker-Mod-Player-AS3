Attribute VB_Name = "modSplitter"
'This work is published under the Creative Commons BY-NC license available at:
'http://creativecommons.org/licenses/by-nc/3.0/
'
'Author: senseitg@gmail.com
'
'Contact the author for commercial licensing information.

Option Explicit

Private Declare Function htonl Lib "wsock32.dll" (ByVal hostlong As Long) As Long
Private Declare Function htons Lib "wsock32.dll" (ByVal hostshort As Integer) As Integer
Private Declare Function ntohl Lib "wsock32.dll" (ByVal netlong As Long) As Long
Private Declare Function ntohs Lib "wsock32.dll" (ByVal netshort As Integer) As Integer

Private Const LITTLE_ENDIAN = False
Private Const BIG_ENDIAN = True

Private Const SAMPLE_CORRECTION = 0

Private bytSound() As Byte
Private endian As Boolean

Private Type Sample
    Name As String
    Length As Integer
    Tuning As Byte
    Volume As Byte
    LoopOffset As Integer
    LoopLength As Integer
    Prepend As Long
    Append As Long
End Type

Private Sub WriteStr(data As String)
    Put #1, , data
End Sub

Private Sub WriteLng(ByVal data As Long)
    If endian Then data = htonl(data)
    Put #1, , data
End Sub

Private Sub WriteInt(ByVal data As Integer)
    If endian Then data = htons(data)
    Put #1, , data
End Sub

Private Sub WriteByte(ByVal data As Byte)
    Put #1, , data
End Sub

Private Sub WriteArr(data() As Byte)
    Put #1, , data
End Sub

Private Function ReadStr(Length As Long) As String
    Dim data As String
    data = Space(Length)
    Get #2, , data
    ReadStr = data
End Function

Private Function ReadLng() As Long
    Dim data As Long
    Get #2, , data
    ReadLng = IIf(endian, ntohl(data), data)
End Function

Private Function ReadInt() As Integer
    Dim data As Integer
    Get #2, , data
    ReadInt = IIf(endian, ntohs(data), data)
End Function

Private Function ReadByte() As Integer
    Dim data As Byte
    Get #2, , data
    ReadByte = data
End Function

Private Function ReadArr(Length As Long) As Byte()
    ReDim data(0 To Length - 1) As Byte
    Get #2, , data
    ReadArr = data
End Function

Function LoopBack(n As Long, max As Long) As Long
    While n < 1
        n = n + max
    Wend
    LoopBack = n
End Function

Sub Main()
    Dim b As Byte, Patterns As Byte, n As Long, z As Long
    Dim SampleCount As Long
    Dim SampleData() As Byte, AllSampleData() As Byte
    Dim Samples(0 To 30) As Sample
    Dim Orders() As Byte, OrderCount As Byte
    Dim temp_b As Long, temp_w As Long
    Dim CellSample As Long
    Dim CellEffect As Long
    Dim CellParam As Long
    Dim CellPeriod As Long
    Dim FixCount As Long

    Dim PeriodTable As Variant
    PeriodTable = Array( _
        Array(856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453, 428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240, 226, 214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113), _
        Array(850, 802, 757, 715, 674, 637, 601, 567, 535, 505, 477, 450, 425, 401, 379, 357, 337, 318, 300, 284, 268, 253, 239, 225, 213, 201, 189, 179, 169, 159, 150, 142, 134, 126, 119, 113), _
        Array(844, 796, 752, 709, 670, 632, 597, 563, 532, 502, 474, 447, 422, 398, 376, 355, 335, 316, 298, 282, 266, 251, 237, 224, 211, 199, 188, 177, 167, 158, 149, 141, 133, 125, 118, 112), _
        Array(838, 791, 746, 704, 665, 628, 592, 559, 528, 498, 470, 444, 419, 395, 373, 352, 332, 314, 296, 280, 264, 249, 235, 222, 209, 198, 187, 176, 166, 157, 148, 140, 132, 125, 118, 111), _
        Array(832, 785, 741, 699, 660, 623, 588, 555, 524, 495, 467, 441, 416, 392, 370, 350, 330, 312, 294, 278, 262, 247, 233, 220, 208, 196, 185, 175, 165, 156, 147, 139, 131, 124, 117, 110), _
        Array(826, 779, 736, 694, 655, 619, 584, 551, 520, 491, 463, 437, 413, 390, 368, 347, 328, 309, 292, 276, 260, 245, 232, 219, 206, 195, 184, 174, 164, 155, 146, 138, 130, 123, 116, 109), _
        Array(820, 774, 730, 689, 651, 614, 580, 547, 516, 487, 460, 434, 410, 387, 365, 345, 325, 307, 290, 274, 258, 244, 230, 217, 205, 193, 183, 172, 163, 154, 145, 137, 129, 122, 115, 109), _
        Array(814, 768, 725, 684, 646, 610, 575, 543, 513, 484, 457, 431, 407, 384, 363, 342, 323, 305, 288, 272, 256, 242, 228, 216, 204, 192, 181, 171, 161, 152, 144, 136, 128, 121, 114, 108), _
        Array(907, 856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453, 428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240, 226, 214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120), _
        Array(900, 850, 802, 757, 715, 675, 636, 601, 567, 535, 505, 477, 450, 425, 401, 379, 357, 337, 318, 300, 284, 268, 253, 238, 225, 212, 200, 189, 179, 169, 159, 150, 142, 134, 126, 119), _
        Array(894, 844, 796, 752, 709, 670, 632, 597, 563, 532, 502, 474, 447, 422, 398, 376, 355, 335, 316, 298, 282, 266, 251, 237, 223, 211, 199, 188, 177, 167, 158, 149, 141, 133, 125, 118), _
        Array(887, 838, 791, 746, 704, 665, 628, 592, 559, 528, 498, 470, 444, 419, 395, 373, 352, 332, 314, 296, 280, 264, 249, 235, 222, 209, 198, 187, 176, 166, 157, 148, 140, 132, 125, 118), _
        Array(881, 832, 785, 741, 699, 660, 623, 588, 555, 524, 494, 467, 441, 416, 392, 370, 350, 330, 312, 294, 278, 262, 247, 233, 220, 208, 196, 185, 175, 165, 156, 147, 139, 131, 123, 117), _
        Array(875, 826, 779, 736, 694, 655, 619, 584, 551, 520, 491, 463, 437, 413, 390, 368, 347, 328, 309, 292, 276, 260, 245, 232, 219, 206, 195, 184, 174, 164, 155, 146, 138, 130, 123, 116), _
        Array(868, 820, 774, 730, 689, 651, 614, 580, 547, 516, 487, 460, 434, 410, 387, 365, 345, 325, 307, 290, 274, 258, 244, 230, 217, 205, 193, 183, 172, 163, 154, 145, 137, 129, 122, 115), _
        Array(862, 814, 768, 725, 684, 646, 610, 575, 543, 513, 484, 457, 431, 407, 384, 363, 342, 323, 305, 288, 272, 256, 242, 228, 216, 203, 192, 181, 171, 161, 152, 144, 136, 128, 121, 114) _
    )

    endian = BIG_ENDIAN
    Open Replace(Command, """", "") + ".hdr" For Output As #1: Close #1
    Open Replace(Command, """", "") + ".hdr" For Binary Access Write As #1
    Open Replace(Command, """", "") For Binary Access Read As #2
    Debug.Print "Title: " + ReadStr(20)
    For n = 0 To 30
        Samples(n).Name = ReadStr(22)
        Samples(n).Length = ReadInt() * 2
        Samples(n).Tuning = ReadByte()
        Samples(n).Volume = ReadByte()
        Samples(n).LoopOffset = ReadInt() * 2
        Samples(n).LoopLength = ReadInt()
        Samples(n).LoopLength = IIf(Samples(n).LoopLength < 2, 0, Samples(n).LoopLength * 2)
        
        WriteInt Samples(n).Length \ 2
        If Samples(n).Length <> 0 Then
            Debug.Print "Sample " + IIf(n < 16, "0", "") + Hex(n) + ": " + Samples(n).Name
            WriteByte Samples(n).Tuning
            WriteByte Samples(n).Volume
            WriteInt Samples(n).LoopOffset \ 2
            WriteInt Samples(n).LoopLength \ 2
        End If
    Next

    OrderCount = ReadByte()
    WriteByte OrderCount
    Debug.Print "Repeat/tracker ID: " + CStr(ReadByte())
    Debug.Print "Order:";
    Orders = ReadArr(128)
    For n = 0 To 127
        If n < OrderCount Then Debug.Print " " + CStr(Orders(n));
        If Orders(n) >= Patterns Then Patterns = Orders(n) + 1
    Next
    Debug.Print ""
    ReDim Preserve Orders(OrderCount - 1)
    
    WriteArr Orders
    
    Debug.Print "Tracker: " + ReadStr(4)
    
    Debug.Print "Patterns: " + CStr(Patterns)

'    '3-cell coding (reduce patterns by 25%)
'    For n = 0 To Patterns * 256 - 1
'        temp_b = ReadByte()
'        temp_w = (temp_b And &HF) * &H100
'        CellSample = temp_b And &HF0
'        temp_b = ReadByte()
'        temp_w = temp_w Or temp_b
'        temp_b = ReadByte()
'        CellSample = CellSample Or (temp_b \ &H10)
'        CellEffect = (temp_b And &HF) * &H10
'        CellParam = ReadByte()
'        CellPeriod = &H7F
'        If temp_w Then
'            For z = 0 To 35
'                If PeriodTable(0)(z) = temp_w Then
'                    CellPeriod = z
'                    Exit For
'                End If
'            Next
'            If z = 36 Then
'                Debug.Print "Not a ProTracker MOD!"
'                End
'            End If
'        End If
'        WriteByte CellEffect Or (CellParam \ &H10)
'        WriteByte ((CellParam And &HF) * &H10) Or (CellSample \ &H2)
'        WriteByte ((CellSample And &H1) * &H80) Or CellPeriod
'    Next
'    'else...
    WriteArr ReadArr(CLng(Patterns) * 1024)

    Close #1

    'Read sample data
    For n = 0 To 30
        If Samples(n).Length Then
            ReDim SampleData(0 To Samples(n).Length - 1) As Byte
            Get #2, , SampleData
            'fix data
            If Samples(n).LoopLength Then
                'Unroll forwards
                ReDim Preserve SampleData(UBound(SampleData) + SAMPLE_CORRECTION)
                For z = 0 To SAMPLE_CORRECTION - 1
                    SampleData(UBound(SampleData) - SAMPLE_CORRECTION + z) = SampleData((z Mod (Samples(n).LoopLength - Samples(n).LoopOffset)) + Samples(n).LoopOffset)
                Next
                'Unroll backwards
                If Samples(n).LoopOffset < SAMPLE_CORRECTION Then
                    FixCount = SAMPLE_CORRECTION - Samples(n).LoopOffset
                    ReDim Preserve SampleData(UBound(SampleData) + FixCount)
                    For z = UBound(SampleData) - FixCount To 0 Step -1
                        SampleData(z + FixCount) = SampleData(z)
                    Next
                    For z = FixCount - 1 To 0 Step -1
                        SampleData(z) = SampleData(Samples(n).LoopOffset + Samples(n).LoopLength - LoopBack(z - FixCount, Samples(n).LoopLength - Samples(n).LoopOffset))
                    Next
                End If
            Else
                'Add some silence
                ReDim Preserve SampleData(UBound(SampleData) + SAMPLE_CORRECTION)
                For z = UBound(SampleData) - SAMPLE_CORRECTION To 0 Step -1
                    SampleData(z + SAMPLE_CORRECTION \ 2) = SampleData(z)
                Next
            End If
            
            On Error Resume Next
            ReDim Preserve AllSampleData(UBound(AllSampleData) + UBound(SampleData) + 1)
            If Err.Number Then
                ReDim AllSampleData(UBound(SampleData))
            End If
            On Error GoTo 0
            For z = 0 To UBound(SampleData)
                AllSampleData(UBound(AllSampleData) - UBound(SampleData) + z) = SampleData(z) Xor &H80
            Next
        End If
    Next
    
    Close #2

    'Write sample data as wav-file
    endian = LITTLE_ENDIAN
    SampleCount = UBound(AllSampleData) + 1
    Open Replace(Command, """", "") + ".wav" For Output As #1: Close #1
    Open Replace(Command, """", "") + ".wav" For Binary Access Write As #1
    WriteStr "RIFF"             'RIFF: header
    WriteLng SampleCount + 36   'RIFF: chunk size
    WriteStr "WAVE"             'RIFF: type
    WriteStr "fmt "             'Chunk: header
    WriteLng 16                 'Chunk: size
    WriteInt 1                  'Chunk: compression = pcm
    WriteInt 1                  'Chunk: channels = mono
    WriteLng 11025              'Chunk: samplerate = 11kHz
    WriteLng 11025              'Chunk: bpp = 11kHz
    WriteInt 1                  'Chunk: block align = 1 byte (mono, 8 bits)
    WriteInt 8                  'Chunk: bits per sample = 8
    WriteStr "data"             'Data: header
    WriteLng SampleCount        'Data: size
    WriteArr AllSampleData      'Data: samples
    Close #1

    End
End Sub
