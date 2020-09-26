import re
import pandas as pd

def rw_parse ():
    print("========================rw_parse start===================================")
    with open ("cpu_rw_1.txt","r") as reader1 ,open ("cpu_rw_2.txt","r") as reader2,open ("cpu_rw_3.txt","r") as reader3:
        rw_table = []
        cycle_rw = []
        rw_list = []
        current_time = 0
        lines = reader1.readlines()
        for line  in lines[:-1] :
            line = line.strip()
            sim_time = line.split("cycle ")[0].strip()
            rw_info = line.split("cycle ")[1].strip()[1:]
            if current_time == int(sim_time):
                cycle_rw.append(rw_info)
            else:
                rw_list.append(current_time)
                rw_list.append(cycle_rw)
                rw_table.append(rw_list)
                current_time = int(sim_time)
                cycle_rw = []
                rw_list = []
        rw_list.append(current_time)
        rw_list.append(cycle_rw)
        rw_table.append(rw_list)
        current_time = int(sim_time)
        cycle_rw = []
        rw_list = []
        current_time = 0
        lines = reader2.readlines()
        for line  in lines[:-1] :
            line = line.strip()
            sim_time = line.split("cycle ")[0].strip()
            rw_info = line.split("cycle ")[1].strip()[1:]
            if current_time == int(sim_time):
                cycle_rw.append(rw_info)
            else:
                rw_list.append(current_time)
                rw_list.append(cycle_rw)
                rw_table[(int(current_time/10000))][1].append(rw_list)
                current_time = int(sim_time)
                cycle_rw = []
                rw_list = []
        rw_list.append(current_time)
        rw_list.append(cycle_rw)
        rw_table[(int(current_time/10000))][1].append(rw_list)
        current_time = int(sim_time)
        cycle_rw = []
        rw_list = []
        current_time = 0
        lines = reader3.readlines()
        for line  in lines[:-1] :
            line = line.strip()
            sim_time = line.split("cycle ")[0].strip()
            rw_info = line.split("cycle ")[1].strip()[1:]
            if current_time == int(sim_time):
                cycle_rw.append(rw_info)
            else:
                rw_list.append(current_time)
                rw_list.append(cycle_rw)
                rw_table[(int(current_time/10000))][1].append(rw_list)
                current_time = int(sim_time)
                cycle_rw = []
                rw_list = []
        rw_list.append(current_time)
        rw_list.append(cycle_rw)
        rw_table[(int(current_time/10000))][1].append(rw_list)
        current_time = int(sim_time)
        cycle_rw = []
        rw_list = []
    df_rw_table = pd.DataFrame(rw_table,columns=['sim_time', 'assign'])
    df_rw_table.to_csv("assign_log.csv",index=False)
    print("========================rw_parse start===================================")






def rewrite_format():
    print("========================rewrite_format start===================================")

    with open('picorv32_pcpi_fast_mul.v', "r") as reader:
        with open ('picorv32_pcpi_fast_mul_format.v', "w") as writer:
            # for i,line in enumerate(reader.readlines(),0):
            
            for line in reader:

                line = line.strip()
                if (re.match(" ?if ?",line)):
                    if line.endswith("begin"):
                            writer.write(("{}\n").format(line))
                            
                    else:
                        if line.endswith(";"):
                            line = re.split(r"\) ",line)
                            writer.write(("{}) begin\n").format(line[0]))
                            writer.write(("{}\n").format(line[1]))
                            writer.write("end\n")
                            
                        elif line.endswith(")"):
                            writer.write(("{} begin\n").format(line))
                            next_line = reader.next().strip()
                            writer.write(("{} \n").format(next_line))
                            writer.write("end\n")
                        else:
                            if line.endswith(";"):
                                
                                writer.write(("{}\n").format(line))
                            elif   line.find("begin") == -1:  
                                while not(line.endswith(";")):
                                    writer.write(("{}").format(line.replace("assign","")))
                                    line = reader.next().strip()
                                writer.write(("{}\n").format(line.replace("assign","")))
                                writer.write("end\n")
                            else:
                                writer.write(("{}\n").format(line))  
                elif line.find(": ") is not -1 and line.find("?") == -1 and \
                    line.find("wire") == -1 and line.find("reg") is -1 and \
                    line.find("$") is -1 and line.find("para") is -1 and \
                    line.find("put") is -1 and line.find("+: ") is -1:
                    if line.endswith(":"):
                        writer.write(("{} begin\n").format(line))
                        next_line = reader.next().strip()
                        writer.write(("{} \n").format(next_line))
                        writer.write("end\n")
                    else:
                        
                        if  (line.find("begin")) == -1 and line.endswith(";"):
                            writer.write(("{}: begin\n").format(re.split(r"(:)",line)[0]))
                            string = ""
                            for char in re.split(r"(:)",line)[2:]:
                                string += char
                            writer.write(("{}\n").format(string))
                            writer.write("end\n")

                        else:
                            if line.endswith(";"):
                                writer.write(("{}\n").format(line))
                            elif   line.find("begin") == -1:  
                                while not(line.endswith(";")):
                                    writer.write(("{}").format(line.replace("assign","")))
                                    line = reader.next().strip()
                                writer.write(("{}\n").format(line.replace("assign","")))
                                writer.write("end\n")
                            else:
                                writer.write(("{}\n").format(line))
                else:

                    if line.find("=") is not -1 and not line.endswith(";") and line.find("para") is  -1:
                        if line.endswith(";"):
                                
                            writer.write(("{}\n").format(line))
                        elif   line.find("begin") == -1  :  
                            while not(line.endswith(";")):
                                writer.write(("{}").format(line))
                                line = reader.next().strip()
                            writer.write(("{}\n").format(line))
                        else:
                            writer.write(("{}\n").format(line))  
                    elif line.endswith(":"):
                        writer.write(("{} begin\n").format(line))
                        next_line = reader.next().strip()
                        writer.write(("{} \n").format(next_line))
                        writer.write("end\n")
                    elif line.find("always") is not -1 and line.find("begin") is -1:
                        if line.endswith(";"):
                            writer.write(("{}) begin\n").format(line.split(")")[0]))
                            writer.write(("{} \n").format(line.split(")")[1]))
                            writer.write("end \n")
                        else:
                            writer.write(("{} begin\n").format(line))
                            next_line = reader.next().strip()
                            writer.write(("{} \n").format(next_line))
                            writer.write("end\n")
                    else:
                        if line.find(":") is not -1 and line.find("[") is -1 and line.find("=") is not -1 and line.find("?") is -1 :
                            writer.write(("{}: begin\n").format(line.split(":")[0]))
                            writer.write(("{} \n").format(line.split(":")[1]))
                            writer.write("end \n")
                        else:
                            writer.write(('{}\n').format(line))
    
    print("========================rewrite_format done===================================")
def add_display():
    print("========================add_display start===================================")
    line_count = 0 
    with open('picorv32_pcpi_fast_mul_format.v', "r") as reader:
        with open ('picorv32_pcpi_fast_mul_display.v', "w") as writer:
            for line in reader:
                line =line.strip()
                if  (line.find("=")) is not -1 and line.find("para") is -1 and \
                    line.find("wire") is -1 and line.find("assign") is -1\
                        and line.find("for") is -1 :
                    if line.find("if") is not -1:
                        line_count += 1
                        writer.write(("$fwrite(f,\"%0t cycle :picorv32.v:{}\\n\"  , $time); \n").format(line_count))
                        writer.write(("{} \n").format(line))
                        line_count += 1
                    elif line.find("case") is not -1 and line.find("(") is not -1:
                        line_count += 1
                        writer.write(("$fwrite(f,\"%0t cycle :picorv32.v:{}\\n\"  , $time); \n").format(line_count))
                        writer.write(("{} \n").format(line))
                        line_count += 1
                    else:
                        writer.write(("{} \n").format(line))
                        line_count += 1
                        writer.write(("$fwrite(f,\"%0t cycle :picorv32.v:{}\\n\"  , $time); \n").format(line_count))
                        line_count += 1
                else:
                    if line.find("if") is not -1 and line.find("(") is not -1:
                        line_count += 1
                        writer.write(("$fwrite(f,\"%0t cycle :picorv32.v:{}\\n\"  , $time); \n").format(line_count+1))
                        writer.write(("{} \n").format(line))
                        line_count += 1
                    elif line.find("case") is not -1 and line.find("(") is not -1:
                        line_count += 1
                        writer.write(("$fwrite(f,\"%0t cycle :picorv32.v:{}\\n\"  , $time); \n").format(line_count+1))
                        writer.write(("{} \n").format(line))
                        line_count += 1
                    elif line.find("assign") is not -1 or(line.find("wire") is not -1 and line.find("=") is not -1):
                        writer.write(("{} \n").format(line))
                        line_count += 1
                        writer.write("always@* begin \n")
                        line_count += 1
                        writer.write(("$fwrite(f,\"%0t cycle :picorv32.v:{}\\n\"  , $time); \n").format(line_count-1))
                        line_count += 1
                        writer.write("end \n")
                        line_count += 1

                    else:
                        writer.write(("{} \n").format(line))
                        line_count += 1
                




    print("========================add_display done===================================")





if __name__ =="__main__":
    # parse_reg_name()
    # parse_reg_rw()
    # rewrite_format()
    # add_display()
    rw_parse()

    print("========================__main__ done===================================")